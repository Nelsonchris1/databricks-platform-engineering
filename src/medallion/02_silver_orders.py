# Databricks notebook source
# MAGIC %md
# MAGIC # Silver — validated, conformed orders
# MAGIC
# MAGIC Silver turns raw strings into a trustworthy, typed table. It has three jobs:
# MAGIC
# MAGIC 1. **Conform** — cast to real types, trim whitespace, normalise status casing.
# MAGIC 2. **Validate** — reject rows that break the contract, with a stated reason.
# MAGIC 3. **Deduplicate** — one row per `order_id`, keeping the latest restatement.
# MAGIC
# MAGIC Bad rows are *quarantined*, never silently dropped. Everything Bronze delivered
# MAGIC ends up in exactly one of `orders` or `orders_quarantine`, which makes the split
# MAGIC auditable and gives the row-count reconciliation below something to assert on.

# COMMAND ----------

from pyspark.sql import Window
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

dbutils.widgets.text("catalog", "dev", "Unity Catalog catalog")
CATALOG = dbutils.widgets.get("catalog").strip()

if not CATALOG:
    raise ValueError("catalog must not be empty")

BRONZE_TABLE = f"{CATALOG}.bronze.orders_raw"
SILVER_TABLE = f"{CATALOG}.silver.orders"
QUARANTINE_TABLE = f"{CATALOG}.silver.orders_quarantine"

VALID_STATUSES = ["COMPLETED", "PENDING", "CANCELLED"]

AMOUNT_TYPE = DecimalType(12, 2)

# COMMAND ----------

bronze_df = spark.table(BRONZE_TABLE)

# Reusable cast/conform expressions. Defining them once keeps the validation rules
# and the final projection honest about each other: validation checks the same
# tolerant cast expressions that Silver will actually store.
order_id_expr = F.trim(F.col("order_id"))
customer_id_expr = F.trim(F.col("customer_id"))
timestamp_expr = F.to_timestamp(F.trim(F.col("order_timestamp")))
# Source fields are untrusted strings. Databricks uses ANSI casting, where an
# ordinary cast raises on malformed input. try_cast returns NULL instead so the
# validation rules can route malformed rows to quarantine.
quantity_expr = F.expr("try_cast(quantity AS INT)")
unit_price_expr = F.expr("try_cast(unit_price AS DECIMAL(10, 2))")
status_expr = F.upper(F.trim(F.col("status")))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Validation rules
# MAGIC
# MAGIC Each rule is a `(condition, reason)` pair. `concat_ws` drops the NULLs produced by
# MAGIC a `when` that did not fire, so a row collects every reason it failed — not just
# MAGIC the first — and a clean row ends up with an empty string.
# MAGIC
# MAGIC A failed `try_cast` surfaces as NULL, so `"abc"` as a quantity is caught by the
# MAGIC same rule as a zero quantity without failing the Spark job under ANSI mode.

# COMMAND ----------

VALIDATION_RULES = [
    (order_id_expr.isNull() | (order_id_expr == ""), "missing order_id"),
    (customer_id_expr.isNull() | (customer_id_expr == ""), "missing customer_id"),
    (quantity_expr.isNull() | (quantity_expr <= 0), "non-positive or non-numeric quantity"),
    (unit_price_expr.isNull() | (unit_price_expr < 0), "negative or non-numeric unit_price"),
    (F.col("status").isNull() | ~status_expr.isin(VALID_STATUSES), "unsupported status"),
    # Not in the stated contract, but Gold partitions by order_date, so an
    # unparseable timestamp cannot be allowed through.
    (timestamp_expr.isNull(), "unparseable order_timestamp"),
]

validated_df = bronze_df.withColumn(
    "rejection_reason",
    F.concat_ws("; ", *[F.when(condition, F.lit(reason)) for condition, reason in VALIDATION_RULES]),
)

invalid_df = validated_df.filter(F.col("rejection_reason") != "")
candidate_df = validated_df.filter(F.col("rejection_reason") == "")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Deduplicate on `order_id`
# MAGIC
# MAGIC Bronze carries a restatement of `ORD-1002` — same order, later timestamp, corrected
# MAGIC quantity. The newest row wins; a stable hash of the raw business fields breaks an
# MAGIC equal-timestamp tie so a rerun on identical input keeps the same row.
# MAGIC
# MAGIC Superseded rows are quarantined rather than dropped, so the audit trail stays
# MAGIC complete.

# COMMAND ----------

raw_business_columns = [
    "order_id",
    "customer_id",
    "order_timestamp",
    "product",
    "quantity",
    "unit_price",
    "status",
]

dedupe_tiebreaker = F.sha2(
    F.concat_ws(
        "||",
        *[F.coalesce(F.col(name), F.lit("<NULL>")) for name in raw_business_columns],
    ),
    256,
)

dedupe_window = Window.partitionBy(order_id_expr).orderBy(
    timestamp_expr.desc(),
    dedupe_tiebreaker.desc(),
)

ranked_df = candidate_df.withColumn("row_num", F.row_number().over(dedupe_window))

superseded_df = (
    ranked_df.filter(F.col("row_num") > 1)
    .drop("row_num")
    .withColumn("rejection_reason", F.lit("superseded duplicate order_id"))
)

deduplicated_df = ranked_df.filter(F.col("row_num") == 1).drop("row_num", "rejection_reason")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Project the Silver contract
# MAGIC
# MAGIC `total_amount` is computed once here so every downstream consumer agrees on what
# MAGIC an order is worth. Money stays `DECIMAL`, never `DOUBLE`.

# COMMAND ----------

silver_df = deduplicated_df.select(
    order_id_expr.alias("order_id"),
    customer_id_expr.alias("customer_id"),
    timestamp_expr.alias("order_timestamp"),
    F.to_date(timestamp_expr).alias("order_date"),
    F.trim(F.col("product")).alias("product"),
    quantity_expr.alias("quantity"),
    unit_price_expr.alias("unit_price"),
    (quantity_expr * unit_price_expr).cast(AMOUNT_TYPE).alias("total_amount"),
    status_expr.alias("status"),
    F.col("ingested_at"),
    F.col("source_file"),
)

# Both quarantine branches keep the original untyped values, so you can see exactly
# what arrived — a cast to NULL would hide that the quantity was the string "abc".
quarantine_df = invalid_df.unionByName(superseded_df).withColumn(
    "quarantined_at", F.current_timestamp()
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Write both outputs
# MAGIC
# MAGIC `overwrite` again: Silver is a pure function of Bronze, so a rerun should reproduce
# MAGIC the table rather than accumulate copies of it.

# COMMAND ----------

(
    silver_df.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(SILVER_TABLE)
)

(
    quarantine_df.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(QUARANTINE_TABLE)
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Data-quality assertions
# MAGIC
# MAGIC These run *after* the write and raise on failure, which fails the Databricks task
# MAGIC and stops Gold from running on bad data. In production these would also publish a
# MAGIC metric, so a passing run is observable and not just a silent success.

# COMMAND ----------

silver_written = spark.table(SILVER_TABLE)

duplicate_ids = silver_written.groupBy("order_id").count().filter(F.col("count") > 1).count()
assert duplicate_ids == 0, f"{duplicate_ids} duplicate order_id values survived deduplication"

negative_totals = silver_written.filter(F.col("total_amount") < 0).count()
assert negative_totals == 0, f"{negative_totals} rows have a negative total_amount"

missing_ids = silver_written.filter(F.col("order_id").isNull() | (F.col("order_id") == "")).count()
assert missing_ids == 0, f"{missing_ids} rows have a missing order_id"

# Every Bronze row must land in exactly one output.
bronze_count = bronze_df.count()
silver_count = silver_written.count()
quarantine_count = spark.table(QUARANTINE_TABLE).count()
assert bronze_count == silver_count + quarantine_count, (
    f"row reconciliation failed: {bronze_count} bronze != "
    f"{silver_count} silver + {quarantine_count} quarantined"
)

print(f"OK — {silver_count} valid, {quarantine_count} quarantined, {bronze_count} in")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Why each row was rejected

# COMMAND ----------

display(
    spark.table(QUARANTINE_TABLE)
    .groupBy("rejection_reason")
    .count()
    .orderBy(F.col("count").desc())
)
