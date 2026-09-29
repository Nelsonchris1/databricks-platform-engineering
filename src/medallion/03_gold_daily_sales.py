# Databricks notebook source
# MAGIC %md
# MAGIC # Gold — daily sales
# MAGIC
# MAGIC Gold answers a business question rather than describing a source system. It is
# MAGIC small, aggregated and safe to hand to a dashboard.
# MAGIC
# MAGIC Two modelling decisions worth stating out loud:
# MAGIC
# MAGIC - Only `COMPLETED` orders count as revenue. Pending and cancelled orders exist in
# MAGIC   Silver but are not sales, and quietly including them is how revenue gets
# MAGIC   overstated.
# MAGIC - Gold reads Silver, never Bronze. It inherits Silver's validation instead of
# MAGIC   re-implementing it, so there is one definition of a valid order.

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

dbutils.widgets.text("catalog", "dev", "Unity Catalog catalog")
CATALOG = dbutils.widgets.get("catalog").strip()

if not CATALOG:
    raise ValueError("catalog must not be empty")

SILVER_TABLE = f"{CATALOG}.silver.orders"
GOLD_TABLE = f"{CATALOG}.gold.daily_sales"

REVENUE_STATUS = "COMPLETED"
REVENUE_TYPE = DecimalType(14, 2)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Aggregate completed orders by day

# COMMAND ----------

completed_orders = spark.table(SILVER_TABLE).filter(F.col("status") == REVENUE_STATUS)

daily_sales_df = (
    completed_orders.groupBy("order_date")
    .agg(
        F.count("*").alias("order_count"),
        F.countDistinct("customer_id").alias("distinct_customer_count"),
        F.sum("quantity").cast("long").alias("units_sold"),
        F.sum("total_amount").cast(REVENUE_TYPE).alias("total_revenue"),
    )
    .orderBy("order_date")
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Write the table
# MAGIC
# MAGIC `overwrite` keeps the full-refresh contract of the layers below: Gold is a pure
# MAGIC function of Silver, so rerunning reproduces it exactly. At real volumes this would
# MAGIC become an incremental `MERGE` on `order_date` rather than a full rebuild.

# COMMAND ----------

(
    daily_sales_df.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(GOLD_TABLE)
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Data-quality assertion

# COMMAND ----------

gold_written = spark.table(GOLD_TABLE)

negative_revenue = gold_written.filter(F.col("total_revenue") < 0).count()
assert negative_revenue == 0, f"{negative_revenue} day(s) have negative total_revenue"

assert gold_written.count() > 0, "daily_sales is empty — no completed orders reached Gold"

print(f"OK — {gold_written.count()} day(s) written to {GOLD_TABLE}")

# COMMAND ----------

display(gold_written.orderBy("order_date"))
