# Lab 9, Part 4: Google Cloud's AI and data services

Three demos in the console of the project `spry-anndizhak-2026`, each with a
screenshot for the submission, and the two questions of Part 4.

## 1. BigQuery: a query over a public dataset

The dataset is `bigquery-public-data.thelook_ecommerce`, a synthetic shop
with orders, order items and their prices. It is the closest public
counterpart of the payments from Lab 8. The query gives the monthly revenue by
order status for the last 24 full months:

```sql
SELECT
  DATE_TRUNC(DATE(created_at), MONTH) AS month,
  status,
  COUNT(*) AS items,
  ROUND(SUM(sale_price), 2) AS revenue_usd
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE DATE(created_at) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 24 MONTH)
  AND DATE(created_at) < DATE_TRUNC(CURRENT_DATE(), MONTH)
GROUP BY month, status
ORDER BY month, status
```

**Bytes processed:** 4,777,479 bytes (≈ 4.8 MB), from a dry run on
2026-11-14. BigQuery bills at least 10 MB per query, and the first 1 TiB a
month is free, so this query costs $0. Only the three columns it reads are
scanned (`created_at`, `status`, `sale_price`): BigQuery stores columns
separately, and `SELECT *` on the same table would scan far more. The data is
regenerated daily, so the number can change slightly.

## 2. Looker Studio: a chart over the result

The chart is a stacked time series: `month` as the dimension, `revenue_usd`
as the metric, broken down by `status`. It is opened from the query result
(Open in → Looker Studio), so no table is stored. Looker Studio is free.

## 3. Document AI: OCR on one document

The processor is **Enterprise Document OCR**, in the region `us`, named
`lab9-ocr`. It runs on one PDF or photo, a receipt or a handwritten page. The
first 1,000 pages a month are free, then $1.50 per 1,000.

## Think about it: Document AI or a general LLM (Lab 6)?

Lab 6 parses a pasted agenda with Claude on Bedrock. Document AI is the
better tool when the input is **a document as an image**:

- scanned forms, receipts, invoices or IDs;
- handwriting, tables, checkboxes, the layout of a page.

It returns every word with its bounding box and a confidence score. The same
input gives the same output, and the price is per page ($1.50 per 1,000 for
OCR). For a fixed form, Form Parser or a custom extractor gives a schema that
can be checked field by field.

A general model is the better tool when the input is **free text whose meaning
has to be understood**. That is the case in Lab 6:

- "after lunch" has to become 13:00;
- an agenda that mixes Ukrainian and English has to become one structure;
- the order of items has to be inferred.

OCR would only give back the text the user already pasted. The model costs
per token, can be confidently wrong with a 200 status and has to be validated
(ADR 0006), but no OCR processor can do the understanding step.

The two combine: OCR (Document AI) turns a photo of a printed agenda into
text, and the LLM turns that text into an agenda. Each is used for what it is
good at.

## Link to Lab 8: payments with Athena and Glue

| Lab 8 on AWS | On Google Cloud | What you no longer manage |
| --- | --- | --- |
| S3 bucket with the raw payment files | Cloud Storage bucket, or loaded straight into BigQuery storage | — |
| Glue crawler + Glue Data Catalog (tables, schemas, partitions) | **BigQuery** datasets and tables, whose schema is part of the table (external tables over Cloud Storage if the files stay there) | the crawler and its schedule, and keeping the catalog in sync with the files |
| Glue ETL job (Spark) that cleans and converts to Parquet | **Dataflow** (Apache Beam: the same code for batch and streaming), or plain SQL in BigQuery (`CREATE TABLE … AS SELECT`, scheduled queries) | the DPU sizing, the conversion to Parquet and the partition layout: BigQuery keeps its own columnar format |
| Athena queries | **BigQuery** queries, both billed per byte scanned ($6.25 per TiB, first TiB free) | the query result bucket in S3, workgroups, and the `MSCK REPAIR` / partition projection needed for new partitions |
| QuickSight (or charts by hand) | **Looker Studio**, free, a connector to BigQuery | QuickSight users and SPICE capacity |

The main difference is that BigQuery is storage, catalog and engine in one
service. On AWS the files (S3), the metadata (Glue) and the engine (Athena)
are three services that have to agree with each other. With BigQuery, what is
left to manage is the data model and the bytes each query scans.
