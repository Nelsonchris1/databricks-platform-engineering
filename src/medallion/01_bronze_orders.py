# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze — raw orders ingest
# MAGIC
# MAGIC Bronze lands source data with **minimal transformation** and adds ingestion
# MAGIC metadata. Business fields stay as strings, exactly as a JSON or CSV feed would
# MAGIC deliver them, so that type casting is a deliberate Silver decision rather than
# MAGIC something Bronze hides.
# MAGIC
# MAGIC Bronze does **not** validate. The batch below deliberately contains bad rows —
# MAGIC missing IDs, a non-numeric quantity, a negative price, an unsupported status and
# MAGIC a restated duplicate order — so the Silver layer has something real to reject.

# Adding this here so i see it in databricks

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType

dbutils.widgets.text("catalog", "dev", "Unity Catalog catalog")
CATALOG = dbutils.widgets.get("catalog").strip()

if not CATALOG:
    raise ValueError("catalog must not be empty")

BRONZE_TABLE = f"{CATALOG}.bronze.orders_raw"

# Stands in for the object-storage path a real feed would arrive on. No credentials,
# no mounts: the synthetic batch is defined in-notebook and regenerated on every run.
SOURCE_FILE = "synthetic/orders_2024-03.json"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Synthetic batch
# MAGIC
# MAGIC A fixed literal list, not random generation, so every run produces byte-identical
# MAGIC business data and the downstream row counts are stable enough to assert on.

# COMMAND ----------

# (order_id, customer_id, order_timestamp, product, quantity, unit_price, status)
ORDERS = [
    # --- Clean rows ---------------------------------------------------------
    ("ORD-1001", "CUST-01", "2024-03-01 09:15:00", "Espresso Machine", "1", "249.99", "COMPLETED"),
    ("ORD-1002", "CUST-02", "2024-03-01 10:05:00", "Coffee Grinder", "2", "89.50", "COMPLETED"),
    ("ORD-1003", "CUST-01", "2024-03-01 14:40:00", "Filter Papers", "10", "4.25", "PENDING"),
    ("ORD-1004", "CUST-03", "2024-03-02 08:20:00", "Milk Frother", "1", "39.00", "COMPLETED"),
    ("ORD-1005", "CUST-04", "2024-03-02 11:00:00", "Espresso Machine", "1", "249.99", "CANCELLED"),
    ("ORD-1007", "CUST-05", "2024-03-03 09:45:00", "Descaler", "2", "12.75", "COMPLETED"),
    ("ORD-1008", "CUST-03", "2024-03-03 13:10:00", "Coffee Beans 1kg", "5", "22.00", "COMPLETED"),
    # --- Messy but recoverable: casing and padding that Silver conforms ------
    ("ORD-1006", "CUST-02", "2024-03-02 16:30:00", "Coffee Beans 1kg", "3", "22.00", "completed"),
    ("ORD-1009", "CUST-06", "2024-03-03 17:55:00", "Travel Mug", "4", "15.00", "  PENDING  "),
    # --- Restatement: same order_id, later timestamp, corrected quantity -----
    ("ORD-1002", "CUST-02", "2024-03-01 10:45:00", "Coffee Grinder", "3", "89.50", "COMPLETED"),
    # --- Deliberately invalid ----------------------------------------------
    (None, "CUST-07", "2024-03-03 10:00:00", "Filter Papers", "1", "4.25", "COMPLETED"),
    ("   ", "CUST-08", "2024-03-03 10:15:00", "Travel Mug", "2", "15.00", "COMPLETED"),
    ("ORD-1011", None, "2024-03-03 10:30:00", "Travel Mug", "1", "15.00", "COMPLETED"),
    ("ORD-1012", "CUST-09", "2024-03-03 11:15:00", "Coffee Grinder", "0", "89.50", "COMPLETED"),
    ("ORD-1013", "CUST-10", "2024-03-03 12:00:00", "Descaler", "-2", "12.75", "COMPLETED"),
    ("ORD-1014", "CUST-11", "2024-03-03 12:30:00", "Milk Frother", "1", "-39.00", "COMPLETED"),
    ("ORD-1015", "CUST-12", "2024-03-03 13:45:00", "Espresso Machine", "1", "249.99", "UNKNOWN"),
    ("ORD-1016", "CUST-13", "2024-03-03 14:20:00", "Filter Papers", "abc", "4.25", "COMPLETED"),
    ("ORD-1018", None, "2024-03-03 15:00:00", "Travel Mug", "-1", "-5.00", "BOGUS"),
]

# Everything arrives as a string, mirroring an untyped file feed.
RAW_SCHEMA = StructType(
    [
        StructField("order_id", StringType(), nullable=True),
        StructField("customer_id", StringType(), nullable=True),
        StructField("order_timestamp", StringType(), nullable=True),
        StructField("product", StringType(), nullable=True),
        StructField("quantity", StringType(), nullable=True),
        StructField("unit_price", StringType(), nullable=True),
        StructField("status", StringType(), nullable=True),
    ]
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Add ingestion metadata and write
# MAGIC
# MAGIC `ingested_at` is the one intentionally non-deterministic column: it records when
# MAGIC *this* run landed the batch, which is what audit metadata is for.
# MAGIC
# MAGIC The write uses `overwrite`, so rerunning replaces the batch rather than appending
# MAGIC it again. That is what keeps the notebook idempotent — a second run leaves the
# MAGIC same 19 rows, not 38.

# COMMAND ----------

bronze_df = (
    spark.createDataFrame(ORDERS, schema=RAW_SCHEMA)
    .withColumn("ingested_at", F.current_timestamp())
    .withColumn("source_file", F.lit(SOURCE_FILE))
)

(
    bronze_df.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(BRONZE_TABLE)
)

print(f"Wrote {bronze_df.count()} rows to {BRONZE_TABLE}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Inspect what landed

# COMMAND ----------

display(spark.table(BRONZE_TABLE).orderBy("order_timestamp"))
