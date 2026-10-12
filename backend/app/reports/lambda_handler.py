"""AWS Lambda entry point of the report builder.

Same container image as the API, different handler (ImageConfig.Command in
infra/reports.yml). It runs in the VPC next to Aurora and writes the CSV to S3
through the gateway endpoint. Whoever triggers it may name a week; without one
it builds the previous ISO week. Three event shapes arrive here:

- the schedule (EventBridge Scheduler): {"source": "schedule"}
- a direct invocation, e.g. `make report-invoke`: {"source": "manual", "week": ...}
- an SQS message (Step 4): {"Records": [{"eventSource": "aws:sqs", "body": "{...}"}]}
"""

import asyncio
import json
import logging
import os
from datetime import datetime, timedelta

from app.config import settings
from app.db import wait_for_database
from app.reports.weekly import build_weekly_report, iso_week, report_key

logger = logging.getLogger("meetings.reports")
logger.setLevel(logging.INFO)


def detect_trigger(event: object) -> str:
    """Name what started this invocation, for the first log line."""
    if isinstance(event, dict):
        records = event.get("Records")
        if records and isinstance(records, list):
            return "sqs" if records[0].get("eventSource") == "aws:sqs" else "unknown"
        if event.get("source") == "schedule":
            return "schedule"
    return "manual"


def requests_from(event: object) -> list[dict]:
    """The payloads to build: one per SQS record, or the event itself."""
    if isinstance(event, dict) and isinstance(event.get("Records"), list):
        return [json.loads(record["body"] or "{}") for record in event["Records"]]
    return [event if isinstance(event, dict) else {}]


def default_week(now: datetime | None = None) -> str:
    """The ISO week before the one that is running now, in the app's timezone.

    Monday 07:00 in Kyiv builds the week that ended a few hours earlier.
    """
    now = now or datetime.now(settings.tz)
    return iso_week(now.astimezone(settings.tz).date() - timedelta(days=7))


def _upload(bucket: str, key: str, body: bytes) -> None:
    # boto3 ships with the Lambda base image; imported here so the module also
    # loads in the local test environment, which does not install it.
    import boto3

    boto3.client("s3").put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="text/csv; charset=utf-8",
    )


def build_and_store(week: str) -> dict:
    attempts = asyncio.run(wait_for_database())
    if attempts > 1:
        logger.info("Database reachable after %d attempts", attempts)
    body = build_weekly_report(week)
    key = report_key(week)
    bucket = os.environ["REPORTS_BUCKET"]
    _upload(bucket, key, body)
    logger.info(
        "report stored at s3://%s/%s (%d bytes)",
        bucket,
        key,
        len(body),
        extra={"week": week, "key": key, "bytes": len(body)},
    )
    return {"week": week, "key": key, "bytes": len(body)}


def handler(event, context):
    trigger = detect_trigger(event)
    results = []
    for request in requests_from(event):
        week = request.get("week") or default_week()
        source = request.get("source")
        # The line to look for in CloudWatch: what started the function, and
        # which week it builds. The fields repeat in `extra` for JSON logs.
        logger.info(
            "report-builder triggered trigger=%s week=%s source=%s",
            trigger,
            week,
            source,
            extra={"trigger": trigger, "week": week, "source": source},
        )
        # An exception propagates on purpose: an SQS message then returns to
        # the queue, and after three failures it moves to the dead-letter queue.
        results.append(build_and_store(week))
    return {"trigger": trigger, "reports": results}
