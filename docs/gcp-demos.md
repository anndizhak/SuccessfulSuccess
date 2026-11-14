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

**Bytes processed: 4.56 MB, bytes billed: 10 MB** (the run on 2026-11-14;
the dry run had estimated 4.78 MB, and the data is regenerated daily).
BigQuery bills at least 10 MB per query, and the first 1 TiB a month is free,
so this query costs $0. Only the three columns it reads are scanned
(`created_at`, `status`, `sale_price`): BigQuery stores columns separately, and
`SELECT *` on the same table would scan far more.

## 2. Looker Studio: a chart over the result

The chart is a stacked time series: `month` as the dimension, `revenue_usd`
as the metric, broken down by `status`. It is opened from the query result
(Open in → Looker Studio), so no table is stored. Looker Studio is free.

## 3. Document AI: OCR on one document

The processor is **Enterprise Document OCR**, in the region `us`, named
`lab9-ocr`. The first 1,000 pages a month are free, then $1.50 per 1,000.

**The result.** The input was a photo of handwritten lecture notes in
Cyrillic, on squared paper. The text was recognised only in part and with
errors. The handwriting and the grid lines behind it are the hard case for a
pretrained OCR model. On printed text and forms the same processor is
reliable; on handwriting it is noticeably weaker.

## Think about it: Document AI or a general LLM (Lab 6)?

Lab 6 parses a pasted agenda with Claude on Bedrock. Document AI is the
better tool when the input is **a document as an image**, above all printed
text and forms:

- scanned forms, receipts, invoices or IDs;
- tables, checkboxes, key-value fields and the layout of a page.

It returns every word with its bounding box and a confidence score. The same
input gives the same output, and the price is per page ($1.50 per 1,000 for
OCR). For a fixed form, Form Parser or a custom extractor gives a schema that
can be checked field by field. Handwriting is its weak spot: the demo above
(Cyrillic notes on squared paper) came back only partly right, and each wrong
word still carries a confidence score, so a pipeline can send those pages to a
person.

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

## Link to Lab 8: payments with Kinesis, Firehose, Glue and Athena

Lab 8, Part 4 (`~/OOP Labs/lab8-kinesis`) replayed the 1 October payments
through this pipeline:

- `producer.py` wrote to the Kinesis stream (on-demand, 4 shards, `PartitionKey = invoiceId`).
- Firehose wrote JSON Lines to S3, with dynamic partitioning by event time (`dt = modifiedDate[0:10]`) and a 60 s / 64 MB buffer.
- A Glue crawler built the `lab8_stream.payments_stream` table.
- Athena ran Q1–Q4: volume, failure share by method, failure share per 10 minutes of event time, and late events.
- In parallel, Lambda read each shard's batches and emailed through SNS when failures were above 10 %.

| Lab 8 on AWS | On Google Cloud | What you no longer manage |
| --- | --- | --- |
| Kinesis Data Stream, on-demand ($0.04 per stream-hour, 1 KB per record) | **Pub/Sub** topic, ordering key `invoiceId` | shards and the on-demand/provisioned choice, the fixed stream-hour ($29.20 of the $33 a month in Lab 8 §5.2), the 1 KB rounding. Pub/Sub bills only throughput, and the first 10 GiB a month is free |
| Firehose: 60 s / 64 MB buffer, dynamic partitioning by JQ, an error prefix | A **BigQuery subscription** on the topic (Pub/Sub writes rows straight into a table), or **Dataflow** (the Pub/Sub → BigQuery template) when the events need transforming | the buffer and its 64 MB minimum, the JQ partition key, the files in S3 and the 5 KB rounding. Rows are queryable seconds after they are published |
| S3 `payments-stream/dt=…/` + Glue crawler + Data Catalog (JSON SerDe, 16 columns, partition `dt`) | **BigQuery** table `payments_stream`, partitioned by `DATE(modifiedDate)` (event time) and clustered by `paymentMethod` | the crawler and its 10-minute minimum, registering each new `dt` partition (crawler, `MSCK REPAIR` or partition projection) and the SerDe. The schema is part of the table |
| Athena Q1–Q4 (3.96 MB per query: full scans of JSON) | **BigQuery** with the same SQL (`DISTINCT`, `row_number()`, 10-minute buckets) | the query-result location in the workgroup, and the conversion to Parquet: BigQuery is columnar, so Q2 reads only `invoiceId`, `status`, `modifiedDate` and `paymentMethod` |
| Lambda on Kinesis: batches of ≤1000 records / 60 s per shard, a processing-time window, dedup only inside a batch | **Dataflow** (Apache Beam) streaming job: windows on **event time**, with watermarks, late data and state, which Lab 8 said needs Managed Flink on AWS. For a simple check per message: a Pub/Sub push subscription to Cloud Run | the per-shard checkpoints, the batch window and the state between batches. Exactly-once delivery is an option of the subscription |
| SNS email when failures > 10 % | **Cloud Monitoring** alert policy on a log-based or custom metric, with an email notification channel | the topic, the subscription and its confirmation |
| (no dashboard in Lab 8) | **Looker Studio** over the BigQuery table, e.g. Q3 as a line chart of `failure_pct` per 10 minutes | — |

The main difference is that BigQuery is storage, catalog and engine in one
service. On AWS, the files (S3), the schema (Glue), the engine (Athena) and
the delivery into partitions (Firehose) are four services that have to agree
with each other. That agreement caused the pitfalls listed in Lab 8: the 64 MB
minimum, the Athena output location, and new partitions. On GCP the stream
goes into a partitioned table, and what is left to manage is the data model
and the bytes each query scans.

The fixed cost moves rather than disappears. Pub/Sub and a BigQuery
subscription have no hourly fee, so the Lab 8 month (~3 million events,
~1.2 GB) fits the free tiers. A streaming Dataflow job, needed for event-time
windows, keeps at least one worker running around the clock. That is the
GCP counterpart of the Kinesis stream-hour, and the line to watch.
