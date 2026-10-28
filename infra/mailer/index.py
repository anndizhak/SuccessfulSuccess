import email.utils
import logging
import os
import urllib.parse
from email.message import EmailMessage

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)
s3 = boto3.client("s3")
ses = boto3.client("sesv2")


def detect_trigger(event):
    records = (event or {}).get("Records") or [{}]
    return "s3" if records[0].get("eventSource") == "aws:s3" else "unknown"


def handler(event, context):
    trigger = detect_trigger(event)
    sender = os.environ["REPORT_SENDER"]
    to = [a.strip() for a in os.environ["REPORT_RECIPIENTS"].split(",") if a.strip()]
    sent = []
    for record in (event or {}).get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        log.info(
            "report-mailer triggered trigger=%s event=%s key=%s",
            trigger, record.get("eventName"), key,
            extra={"trigger": trigger, "event": record.get("eventName"),
                   "bucket": bucket, "key": key},
        )
        if not (key.startswith("reports/") and key.endswith(".csv")):
            continue
        csv = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        week = key.rsplit("/", 1)[-1][:-4]
        msg = EmailMessage()
        msg["Subject"] = "Weekly meetings report " + week
        msg["From"] = sender
        msg["To"] = ", ".join(to)
        msg["Date"] = email.utils.formatdate()
        msg.set_content(
            "Hello,\n\nAttached is the meetings report for ISO week "
            + week + ".\n\n- SuccessfulSuccess\n"
        )
        msg.add_attachment(csv, maintype="text", subtype="csv",
                           filename="meetings-" + week + ".csv")
        reply = ses.send_email(
            FromEmailAddress=sender,
            Destination={"ToAddresses": to},
            Content={"Raw": {"Data": msg.as_bytes()}},
        )
        log.info("report emailed key=%s message_id=%s", key, reply["MessageId"],
                 extra={"key": key, "message_id": reply["MessageId"]})
        sent.append(reply["MessageId"])
    return {"trigger": trigger, "sent": sent}
