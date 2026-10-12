# Weekly report — submission evidence

Collected while building the lab, 12 October 2026.

## CloudWatch log lines (item 5)

Log group `/aws/lambda/successfulsuccess-report-builder`, JSON format.

**Schedule** (EventBridge Scheduler, one test run at `rate(5 minutes)`, then the
Monday cron was restored). No week in the event, so the builder took the
previous ISO week:

```json
{"timestamp": "2026-10-12T11:29:16Z", "level": "INFO", "message": "report-builder triggered trigger=schedule week=2026-W41 source=schedule", "logger": "meetings.reports", "requestId": "d06accc4-6375-4abc-bbd0-c1a908a56485", "trigger": "schedule", "week": "2026-W41", "source": "schedule"}
```

**Direct invocation** (`make report-invoke WEEK=2026-W40`, Step 3's manual test;
not one of the three required triggers):

```json
{"timestamp": "2026-10-12T11:27:26Z", "level": "INFO", "message": "report-builder triggered trigger=manual week=2026-W40 source=manual", "logger": "meetings.reports", "requestId": "50f4d9a2-7994-40b7-a178-b9b6aa1192cf", "trigger": "manual", "week": "2026-W40", "source": "manual"}
```

**SQS message** (`make report-now WEEK=2026-W39`: the Lambda service took the
message off `successfulsuccess-report-requests` and invoked the builder):

```json
{"timestamp": "2026-10-12T11:54:52Z", "level": "INFO", "message": "report-builder triggered trigger=sqs week=2026-W39 source=make", "logger": "meetings.reports", "requestId": "e9387ee8-1f50-5c9d-972b-1daed3ee6c75", "trigger": "sqs", "week": "2026-W39", "source": "make"}
```

Since Step 4 the Monday schedule also sends its request through the queue, so
its runs log `trigger=sqs ... source=schedule`; the `trigger=schedule` line
above is from the schedule invoking the builder directly (the lab's Step 3).

**S3 upload** (`make report-now WEEK=2026-W40`: the builder rewrote
`reports/2026-W40.csv`, and the new object started the mailer). Log group
`/aws/lambda/successfulsuccess-report-mailer`:

```json
{"timestamp": "2026-10-12T12:41:19Z", "level": "INFO", "message": "report-mailer triggered trigger=s3 event=ObjectCreated:Put key=reports/2026-W40.csv", "logger": "root", "requestId": "5bb9202c-4d95-4d3d-b742-31b5777cd4d6", "trigger": "s3", "event": "ObjectCreated:Put", "bucket": "successfulsuccess-reports-347282156909", "key": "reports/2026-W40.csv"}
```

The same run, end to end (12:41:01 → 12:41:20 UTC):

```json
{"timestamp": "2026-10-12T12:41:01Z", "level": "INFO", "message": "report-builder triggered trigger=sqs week=2026-W40 source=make", "logger": "meetings.reports", "requestId": "4b4e03f0-314f-55f9-a42a-60b6e6d48507", "trigger": "sqs", "week": "2026-W40", "source": "make"}
{"timestamp": "2026-10-12T12:41:18Z", "level": "INFO", "message": "report stored at s3://successfulsuccess-reports-347282156909/reports/2026-W40.csv (613 bytes)", "logger": "meetings.reports", "requestId": "4b4e03f0-314f-55f9-a42a-60b6e6d48507", "week": "2026-W40", "key": "reports/2026-W40.csv", "bytes": 613}
{"timestamp": "2026-10-12T12:41:20Z", "level": "INFO", "message": "report emailed key=reports/2026-W40.csv message_id=010001a13021be1d-e596e115-5aea-48ae-9a1b-04bed663f253-000000", "logger": "root", "requestId": "5bb9202c-4d95-4d3d-b742-31b5777cd4d6", "key": "reports/2026-W40.csv", "message_id": "010001a13021be1d-e596e115-5aea-48ae-9a1b-04bed663f253-000000"}
```

## Reports on S3 (item 3)

```
$ aws s3 ls s3://successfulsuccess-reports-347282156909/reports/ --recursive
2026-10-12 14:55:11        638 reports/2026-W39.csv
2026-10-12 15:41:19        613 reports/2026-W40.csv
2026-10-12 14:29:17        411 reports/2026-W41.csv
```

- `2026-W41.csv`: built by the **schedule** (no week given, so the previous ISO week).
- `2026-W39.csv`: built **on demand** with `make report-now WEEK=2026-W39`, through SQS.
- `2026-W40.csv`: first built by a direct invocation while testing Step 3, then
  rebuilt on demand with `make report-now WEEK=2026-W40` (Step 5's end-to-end
  run, which sent the email). Same week, same key: the rebuild overwrote the
  file with identical bytes (613) instead of creating a second one.

## Email screenshot (item 2)

Sent by SES at 12:41:20 UTC (15:41 Kyiv) from and to `annadizhak8@gmail.com`
(email identity only, no domain, as agreed with the lecturer), subject
"Weekly meetings report 2026-W40", attachment `meetings-2026-W40.csv`.
SES message id `010001a13021be1d-e596e115-5aea-48ae-9a1b-04bed663f253-000000`.

_Screenshot: taken (the email arrived in the inbox with the CSV attached)._

## Step 7 checks

### Break it: three attempts, then the dead-letter queue

The builder was changed for a while to raise an error for week 2026-W38, and
`make report-now WEEK=2026-W38` was sent. (For the test only, the queue's
visibility timeout was lowered from 720 s to 130 s so that the retries came
minutes apart instead of 12 minutes apart; it was set back to 720 s afterwards,
and CloudFormation reports the queue `IN_SYNC` with the template.)

```
12:47:06 UTC  attempt 1  trigger=sqs week=2026-W38  ERROR deliberate failure
12:58:59 UTC  attempt 2  trigger=sqs week=2026-W38  ERROR deliberate failure
13:01:08 UTC  attempt 3  trigger=sqs week=2026-W38  ERROR deliberate failure
then          report-requests: 0 messages, report-requests-dlq: 1 message
```

The first retry came after 12 minutes, not 2: SQS can take up to a minute to
apply a changed queue setting, so the first receive still used 720 s.

### Fix it and redrive

The deliberate error was removed and the builder redeployed. Then the message
was moved back with a DLQ redrive (`aws sqs start-message-move-task`, the API
behind "Start DLQ redrive" in the console). It kept its original body:

```
redrive task: COMPLETED, 1 message moved
13:57:09 UTC  builder  trigger=sqs week=2026-W38 source=make
13:57:24 UTC  builder  report stored at .../reports/2026-W38.csv (297 bytes)
13:57:26 UTC  mailer   trigger=s3 event=ObjectCreated:Put key=reports/2026-W38.csv
13:57:26 UTC  mailer   report emailed
```

### The same week twice: two emails

`make report-now WEEK=2026-W39` was sent twice in a row. **Two emails
arrived**, but there is still **one file**:

```
14:04:21 UTC  builder A  trigger=sqs week=2026-W39 source=make
14:04:21 UTC  builder B  trigger=sqs week=2026-W39 source=make
14:04:22 UTC  builder A  report stored at .../reports/2026-W39.csv (638 bytes)
14:04:23 UTC  builder B  report stored at .../reports/2026-W39.csv (638 bytes)
14:04:23 UTC  mailer 1   trigger=s3 event=ObjectCreated:Put  -> report emailed
14:04:24 UTC  mailer 2   trigger=s3 event=ObjectCreated:Put  -> report emailed
```

Why: the report file is idempotent, the email is not. Both requests were real
commands, so two builders ran (in parallel: the queue allows two at once). Both
wrote the same key with the same bytes, so the second write simply replaced the
first. But every write is a new `ObjectCreated` event, even when nothing in the
file changed, and the mailer has no memory of what it already sent. So each
write produced one email.

## Answers

**1. The mailer got the same ObjectCreated event twice, and the person got two
identical emails. Where would you store "this report was already sent", and
what would the key be?**

In a small DynamoDB table, for example `sent-reports`. The mailer runs outside
the VPC, so it cannot reach Aurora, but it can reach DynamoDB, and DynamoDB is
free at this size. The key is the report's key plus its content:
`reports/2026-W39.csv` + the object's ETag (a hash of the file's bytes), for
example `reports/2026-W39.csv#9f2c…`. Before sending, the mailer writes that
item with a condition "only if it does not exist yet". If the write succeeds,
it sends the email; if it fails, this exact report was already sent and it
stops. The condition makes this safe even when two mailers run at the same
second, as in the test above. Using the ETag, and not only the week, means a
report that really changed (for example rebuilt after someone added a meeting)
is still sent again, while an identical copy is not.

**2. The builder in the VPC could not reach SES. List three ways to fix that,
with their monthly cost. Which would you choose with ten more emails a week?
With a million?**

| Option | Monthly cost (us-east-1) | Notes |
|---|---|---|
| NAT gateway | about $33 ($0.045 per hour) plus $0.045 per GB | Gives the whole VPC internet access. Needs private subnets with a route to it. |
| VPC interface endpoint for SES | about $7.30 per Availability Zone ($0.01 per hour), so about $15 for two zones, plus $0.01 per GB | Private path to SES only, nothing else. |
| The split we built (builder in the VPC, mailer outside, joined by an S3 event) | about $0: one more Lambda call and one S3 event per report, inside the free tiers | Needs two functions, and the email is sent a moment after the file is saved. |

SES itself costs the same in all three: $0.10 per 1,000 emails.

- **Ten more emails a week:** the split. It costs nothing while idle, and we
  already have it. A NAT gateway would cost more per month than the whole rest
  of this project.
- **A million emails a week:** the network path hardly matters any more:
  SES alone is about $400 a month (around 4.3 million emails), while the
  endpoint is about $15. I would keep the split, or use the SES interface
  endpoint if the builder had to send directly. I would only add a NAT gateway
  if the VPC also needed general internet access for other reasons. At that
  size the bigger work is elsewhere: production access for SES, a verified
  domain with DKIM, and handling bounces and complaints.

**3. A presigned URL signed with a Lambda role's temporary credentials stops
working when those credentials expire, often within hours. How would you send a
link that works for a week?**

A presigned URL is only valid while the credentials that signed it are valid,
and never longer than 7 days. Ways to get a link that lasts a week:

- **The cleanest: CloudFront signed URLs.** Put a CloudFront distribution in
  front of the reports bucket (the bucket stays private, CloudFront reads it
  through origin access control, like our website). Sign the link with a
  CloudFront key pair, whose private key is kept in Secrets Manager or SSM.
  The expiry is whatever you choose, for example 7 days, and it does not depend
  on any IAM session.
- **Simpler, within S3:** sign with the long-term access key of a dedicated IAM
  user that may only read `reports/*`, its key stored in Secrets Manager. That
  link can last up to the S3 maximum of 7 days.
- **A link that never expires:** link to our own site, for example
  `/reports/2026-W39/`. When someone opens it, the site checks that they are
  signed in (Cognito) and then redirects them to a fresh short-lived presigned
  URL. The link in the email keeps working, and only signed-in people can
  download the file.
