# The weekly meetings report (was infra/reports.yml): EventBridge Scheduler
# (every Monday) and `make report-now` put a request on an SQS queue with a
# dead-letter queue; a builder function in the VPC reads Aurora and writes a
# CSV to a private bucket through a free S3 gateway endpoint. The new file
# starts a mailer function outside the VPC, which emails it through SES.

locals {
  reports_bucket = "${var.project_name}-reports-${local.account_id}"
}

# --- the bucket ---------------------------------------------------------------
# In Terraform the bucket's settings are separate resources that point at it.
# The CloudFormation trick of building the name by hand to break a circular
# dependency is not needed: the notification is its own resource and simply
# comes after the permission.

resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket


  # Changing the name forces a new bucket and loses every report.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-reports-after-90-days"
    status = "Enabled"

    filter {
      prefix = "reports/"
    }

    expiration {
      days = 90
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Plain HTTP requests to the bucket are refused.
resource "aws_s3_bucket_policy" "reports" {
  bucket = aws_s3_bucket.reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.reports.arn, "${aws_s3_bucket.reports.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# Trigger 3: a new report is an event. The builder does not know the mailer
# exists; another listener could be added without touching it.
resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_from_s3]
}

# A function in the VPC has no public IP and the VPC has no NAT gateway, so
# without this a PutObject from the builder hangs. A gateway endpoint is free.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  # PROJECT_NAME comes from default_tags.
  tags = {
    Name = "${var.project_name}-s3"
  }
}

# --- the builder --------------------------------------------------------------
# The role names are the ones CloudFormation generated. A different name would
# mean a new role, not the imported one.

resource "aws_iam_role" "builder" {
  name = "${var.project_name}-reports-BuilderRole-BgAtbtvncSjQ"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

}

# Logs, and the network interfaces a function in a VPC needs.
resource "aws_iam_role_policy_attachment" "builder_vpc" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "builder_write_reports" {
  name = "write-reports"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.reports.arn}/reports/*"
    }]
  })
}

# The Lambda service polls the queue with this role and invokes the function;
# the function itself never connects to SQS.
resource "aws_iam_role_policy" "builder_take_requests" {
  name = "take-report-requests"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
      ]
      Resource = aws_sqs_queue.requests.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = 14
}

resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "Builds the weekly meetings report from Aurora and stores it on S3"
  package_type  = "Image"
  image_uri     = var.builder_image_uri

  # Same image as the API, a different entry point.
  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  architectures = [var.architecture]
  role          = aws_iam_role.builder.arn
  memory_size   = 512

  # Aurora may need time to resume from a pause; 120 s leaves room for it.
  timeout = 120

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      # Like the API's, readable in the function configuration and the state.
      DATABASE_URL            = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${local.db_endpoint}:5432/${var.db_name}"
      APP_TIMEZONE            = var.app_timezone
      REPORTS_BUCKET          = aws_s3_bucket.reports.id
      RUN_MIGRATIONS_ON_START = "false"
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.builder.name
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  # The route to S3 must exist before the first report is written.
  depends_on = [aws_vpc_endpoint.s3]
}

# --- trigger 3: the mailer ----------------------------------------------------
# Not in the VPC: it needs SES on the internet and never touches the database.
# It must never write to reports/, or it would trigger itself forever.

resource "aws_iam_role" "mailer" {
  name = "${var.project_name}-reports-MailerRole-rFPh4EiIIfQn"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

}

resource "aws_iam_role_policy_attachment" "mailer_basic" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer_read_send" {
  name = "read-reports-send-mail"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect    = "Allow"
        Action    = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource  = "*"
        Condition = { StringEquals = { "ses:FromAddress" = var.report_email } }
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = 14
}

# The code that CloudFormation kept inline is now a file, mailer/index.py.
data "archive_file" "mailer" {
  type        = "zip"
  source_file = "${path.module}/mailer/index.py"
  output_path = "${path.module}/.build/mailer.zip"
}

resource "aws_lambda_function" "mailer" {
  function_name = "${var.project_name}-report-mailer"
  description   = "Emails each new weekly report through SES"
  runtime       = "python3.12"
  handler       = "index.handler"
  architectures = ["arm64"]
  memory_size   = 256
  timeout       = 30
  role          = aws_iam_role.mailer.arn

  filename         = data.archive_file.mailer.output_path
  source_code_hash = data.archive_file.mailer.output_base64sha256

  environment {
    variables = {
      REPORT_SENDER     = var.report_email
      REPORT_RECIPIENTS = var.report_email
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.mailer.name
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }
}

# Lets S3, for this bucket in this account only, invoke the mailer. The
# statement ID is the one CloudFormation generated, so it is imported.
resource "aws_lambda_permission" "mailer_from_s3" {
  statement_id   = "${var.project_name}-reports-MailerInvokePermission-cfPaOsRMYRQP"
  function_name  = aws_lambda_function.mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.reports.arn
  source_account = local.account_id
}

# --- SES ----------------------------------------------------------------------
# Only the report address, no domain (agreed with the lecturer).

resource "aws_sesv2_email_identity" "report" {
  email_identity = var.report_email
}

# --- trigger 2: the queue -----------------------------------------------------

# Where a request ends up after three failed attempts, instead of vanishing.
resource "aws_sqs_queue" "requests_dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
  max_message_size          = 1048576 # SQS's current default, 1 MiB
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "requests" {
  name = "${var.project_name}-report-requests"

  # At least 6x the builder's timeout, so a slow build is not started twice.
  visibility_timeout_seconds = 720
  message_retention_seconds  = 345600  # 4 days
  max_message_size           = 1048576 # SQS's current default, 1 MiB
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.requests_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_lambda_event_source_mapping" "requests_to_builder" {
  event_source_arn = aws_sqs_queue.requests.arn
  function_name    = aws_lambda_function.builder.arn

  # One report per invocation: a failure retries that report only.
  batch_size = 1
  enabled    = true

  # Backpressure: at most two builders, each holding an Aurora connection.
  scaling_config {
    maximum_concurrency = 2
  }
}

# --- trigger 1: the schedule --------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-reports-SchedulerRole-7s3b1faK95JB"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Only schedules in this account may use the role.
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })

}

resource "aws_iam_role_policy" "scheduler_send" {
  name = "send-report-requests"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.requests.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  name        = "${var.project_name}-weekly-report"
  group_name  = "default"
  description = "Builds last week's meetings report every Monday morning"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.app_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  # A command with no week: the builder takes the previous ISO week.
  target {
    arn      = aws_sqs_queue.requests.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = "{\"week\": null, \"source\": \"schedule\"}"
  }
}
