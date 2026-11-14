# What the core costs on AWS and on Google Cloud (Lab 9, Part 3)

On-demand list prices in USD, without tax, 730 hours a month: AWS in us-east-1
(as in Lab 4), Google Cloud in us-central1 (the lab's price sheet of
5 November 2026). The services are the ones in [ADR 0008](adr/0008-gcp.md):
on GCP, Cloud SQL (not Firestore), running around the clock.

## The setup that is priced

| Piece | AWS (today) | Google Cloud (Lab 9) |
| --- | --- | --- |
| Frontend + CDN + HTTPS | S3 + CloudFront **Free plan** (WAF included) | Firebase Hosting, Blaze plan with the free quota (10 GB stored, 360 MB a day out) |
| API | Lambda, **arm64, 512 MB**, function URL | Cloud Run, **1 vCPU, 512 MiB**, request-based billing, min 0 / max 2 |
| Database compute | Aurora Serverless v2, 0–1 ACU, pauses after 300 s idle | Cloud SQL db-f1-micro, running (activation policy ALWAYS) |
| Database storage | ~1 GB | 10 GB SSD |
| Registry, secrets, logs | ECR, CloudWatch Logs (30 days) | Artifact Registry, Secret Manager, Cloud Logging |

## Assumptions

The four traffic profiles from Lab 4, with these numbers:

| Profile | Hours with traffic | API requests a month | Site visits a month |
| --- | --- | --- | --- |
| 1. Nobody | 0 | 0 | 0 |
| 2. Class demos (10 × 2 h) | 20 | 20,000 (~1,000 an hour for ~30 people) | 300 |
| 3. Office hours (8 h × 22 days) | 176 | 88,000 (~500 an hour) | 1,000 |
| 4. Busy around the clock | 730 | 26,280,000 (10 a second on average) | 9,000 (300 a day) |

- **An API request** is billed for 100 ms and answers ~2 KB.
- **A site visit** transfers ~0.5 MB (the export is 1.9 MB, ~0.42 MB of it is JavaScript and CSS after compression).
- **Lambda** bills each request on its own: 0.1 s × 0.5 GB = 0.05 GB-s.
- **Cloud Run** bills the time an instance has at least one request in flight. Up to 40 requests share an instance. Profiles 2 and 3 have almost no overlap (requests × 0.1 s). In profile 4, 10 requests a second at 0.1 s each keep an instance busy 1 − e⁻¹ ≈ 63 % of the time: **1,661,000 instance-seconds**.
- **Aurora** runs at its 0.5 ACU floor whenever it is awake ($0.06 an hour), plus 5 minutes before each pause.
- **Free tiers used:**
  - AWS: Lambda 1M requests and 400,000 GB-s a month; CloudFront Free plan; 100 GB a month of internet egress; CloudWatch Logs 5 GB of ingestion.
  - Google Cloud: Cloud Run 2M requests, 180,000 vCPU-s and 360,000 GiB-s; Firebase Hosting 360 MB a day; Artifact Registry 0.5 GB; Secret Manager 6 versions and 10,000 accesses; Cloud Logging 50 GiB.
- **Database load:** profile 4 still fits db-f1-micro and 0.5 ACU; the risks of that are under the totals.

Prices used:

| | Price |
| --- | --- |
| Lambda arm64 | $0.0000133334 per GB-s, $0.20 per million requests |
| Aurora Serverless v2 | $0.12 per ACU-hour, storage $0.10 per GB-month, I/O $0.20 per million |
| CloudWatch Logs | $0.50 per GB ingested |
| Cloud Run (request-based) | $0.000024 per vCPU-s, $0.0000025 per GiB-s, $0.40 per million requests |
| Cloud SQL db-f1-micro | $0.0105 an hour; SSD $0.17 per GB-month (also while stopped) |
| Firebase Hosting | $0.15 per GB beyond 360 MB a day |

## The table for SuccessfulSuccess, per month

| Line | 1. Nobody | 2. Class demos | 3. Office hours | 4. Busy 24/7 |
| --- | --- | --- | --- | --- |
| **AWS**: frontend (CloudFront Free plan) | $0 | $0 | $0 | $0 |
| API (Lambda) | $0 | $0 (1,000 GB-s) | $0 (4,400 GB-s) | **$17.24** |
| Database compute (Aurora) | $0 (paused) | $1.25 (20.8 h) | $10.67 (177.8 h) | **$43.80** (730 h) |
| Database storage + I/O | $0.10 | $0.10 | $0.10 | $1.10 |
| Registry, logs | $0.20 | $0.20 | $0.20 | $1.64 (7.9 GB of logs) |
| **AWS total** | **$0.30** | **$1.55** | **$10.97** | **$63.78** |
| **Google Cloud**: frontend (Firebase Hosting) | $0 | $0 (0.2 GB) | $0 (0.7 GB) | **$6.94** (57 GB, 1.9 GB a day) |
| API (Cloud Run) | $0 | $0 (2,000 s) | $0 (8,800 s) | **$46.44** |
| Database compute (Cloud SQL, running) | **$7.67** | **$7.67** | **$7.67** | $7.67 |
| Database storage (10 GB SSD) | $1.70 | $1.70 | $1.70 | $1.70 |
| Registry, secrets, logs | $0 | $0 | $0 | $0 (26 GB of logs < 50 GiB) |
| **Google Cloud total** | **$9.37** | **$9.37** | **$9.37** | **$62.74** |
| Google Cloud, database stopped when idle (`make gcp-db-stop`) | $1.70 | $1.96 (25 h running) | $3.66 (187 h running) | — |

Profile 4 is a lower bound on both sides:

- Aurora at its 1-ACU ceiling would be $87.60 instead of $43.80.
- If db-f1-micro (shared core, 0.6 GB) is too small at 10 requests a second, db-g1-small costs $25.55 instead of $7.67.

How to check it in the calculators: in the Google Cloud Pricing Calculator, enter Cloud Run (us-central1, 1 vCPU, 0.5 GiB, request-based, the requests and instance-seconds above) and Cloud SQL for PostgreSQL (Enterprise, db-f1-micro, 730 h, 10 GB SSD). In the AWS Pricing Calculator, enter Lambda (us-east-1, arm64, 512 MB, 100 ms, the requests above) and Aurora PostgreSQL Serverless v2 (0.5 ACU × the awake hours, 1 GB). Firebase Hosting is not in the GCP calculator; its line comes from the Firebase pricing page.

## Answers

### Which cloud is cheaper for each profile, and which single line decides it?

| Profile | Cheaper | By | The line that decides it |
| --- | --- | --- | --- |
| 1. Nobody | **AWS** | $9.07 | **Database compute.** Aurora pauses to $0, Cloud SQL bills $7.67 for running idle. Everything else is free on both sides. |
| 2. Class demos | **AWS** | $7.82 | **Database compute.** Aurora is awake 21 hours ($1.25), Cloud SQL 730 ($7.67). Stopping Cloud SQL between demos brings GCP to $1.96, close to AWS, but someone has to start it before each class: it does not wake up on a connection. |
| 3. Office hours | **Google Cloud** | $1.60 | **Database compute** again, the other way round. 178 hours of Aurora at $0.06 ($10.67) cost more than a whole month of db-f1-micro at $0.0105 ($7.67). With a stop/start schedule outside office hours, GCP drops to $3.66. |
| 4. Busy 24/7 | **Google Cloud**, barely | $1.04, a tie within the assumptions | Two lines pull in opposite directions. **Database compute**: Aurora $43.80 against Cloud SQL $7.67, GCP is $36 cheaper. **API**: Cloud Run $46.44 against Lambda $17.24, AWS is $29 cheaper, plus $6.94 of Firebase egress. The database line still decides it. |

In every profile the deciding line is the **database compute**: a database
that pauses (Aurora) wins while the app is mostly idle, and a small instance
that never pauses (Cloud SQL) wins as soon as the app is awake for more than
about 128 hours a month ($7.67 ÷ $0.06 an hour). Compute (Lambda or Cloud Run)
and the CDN only matter at sustained traffic.

### Lab 4: Aurora became more expensive than an instance when something kept it awake. Where is the equivalent trap on GCP?

On GCP the piece that scales to zero is **Cloud Run**, not the database.
Cloud SQL never pauses, so there is nothing to keep awake: you pay for it
around the clock from the start. Like Aurora, Cloud Run with request-based
billing is cheap only while it is mostly idle, and **anything that keeps an
instance busy turns it into the most expensive way to run a server**:

- **Steady traffic.** Profile 4 costs $46.44 a month on Cloud Run. The same container on an e2-small VM costs ~$12.23, and an e2-micro is in the free tier. Instance-based billing ($0.000018 per vCPU-s, no fee per request) is ~$49.93 for a full instance-month: no cheaper here, cheaper only when one instance serves many concurrent requests.
- **What keeps it busy without users:**
  - an uptime check or a warm-up cron every minute;
  - a frontend that polls (TanStack Query's `refetchInterval`; this app sets `refetchOnWindowFocus: false` and no polling);
  - streaming or long-lived requests (SSE, WebSockets), which count as active the whole time;
  - `min_instance_count = 1` "to avoid cold starts". Idle minimum instances are billed all month, at a lower rate.
- **Cloud Run is 1 vCPU, Lambda 512 MB (~⅓ vCPU).** Below one vCPU, Cloud Run allows only one request per instance. Cutting CPU therefore cuts concurrency, which raises instance-seconds again.

Two smaller traps on the same side:

- **Firebase Hosting rewrites.** All `/api/**` traffic passes through Hosting and counts against its 360 MB a day: $6.94 in profile 4, a line AWS does not have, because there the browser calls the function URL directly.
- **Stopping Cloud SQL** saves the compute, but its SSD still bills $1.70 a month. Turning on `disk_autoresize` lets the disk grow and never shrink.

With Firestore instead of Cloud SQL, the trap moves into the code: **reads per
page**. A list that reads 500 documents per visit uses up the free 50,000 reads
a day after 100 visits.
