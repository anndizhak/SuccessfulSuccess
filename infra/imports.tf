# One-time adoption of the resources the three CloudFormation stacks created.
# The IDs come from the stacks before they were deleted (with Retain).
# Delete this file after the first successful apply.

# --- auth ---------------------------------------------------------------------

import {
  to = aws_cognito_user_pool.main
  id = "us-east-1_bKXqzF5Oq"
}

import {
  to = aws_cognito_identity_provider.google
  id = "us-east-1_bKXqzF5Oq:Google"
}

import {
  to = aws_cognito_user_pool_client.web
  id = "us-east-1_bKXqzF5Oq/50cr9th0as2c92ic4g6i9rj419"
}

import {
  to = aws_cognito_user_pool_domain.main
  id = "successfuls"
}

import {
  to = aws_cognito_managed_login_branding.web
  id = "us-east-1_bKXqzF5Oq,53105f6f-2792-415c-b336-850af302e2d5"
}

# --- reports: the bucket and its settings --------------------------------------

import {
  to = aws_s3_bucket.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_s3_bucket_public_access_block.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_s3_bucket_ownership_controls.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_s3_bucket_policy.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_s3_bucket_notification.reports
  id = "successfulsuccess-reports-347282156909"
}

import {
  to = aws_vpc_endpoint.s3
  id = "vpce-0299ff28ed303b876"
}

# --- reports: the builder ------------------------------------------------------

import {
  to = aws_iam_role.builder
  id = "successfulsuccess-reports-BuilderRole-BgAtbtvncSjQ"
}

import {
  to = aws_iam_role_policy_attachment.builder_vpc
  id = "successfulsuccess-reports-BuilderRole-BgAtbtvncSjQ/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

import {
  to = aws_iam_role_policy.builder_write_reports
  id = "successfulsuccess-reports-BuilderRole-BgAtbtvncSjQ:write-reports"
}

import {
  to = aws_iam_role_policy.builder_take_requests
  id = "successfulsuccess-reports-BuilderRole-BgAtbtvncSjQ:take-report-requests"
}

import {
  to = aws_cloudwatch_log_group.builder
  id = "/aws/lambda/successfulsuccess-report-builder"
}

import {
  to = aws_lambda_function.builder
  id = "successfulsuccess-report-builder"
}

# --- reports: the mailer -------------------------------------------------------

import {
  to = aws_iam_role.mailer
  id = "successfulsuccess-reports-MailerRole-rFPh4EiIIfQn"
}

import {
  to = aws_iam_role_policy_attachment.mailer_basic
  id = "successfulsuccess-reports-MailerRole-rFPh4EiIIfQn/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

import {
  to = aws_iam_role_policy.mailer_read_send
  id = "successfulsuccess-reports-MailerRole-rFPh4EiIIfQn:read-reports-send-mail"
}

import {
  to = aws_cloudwatch_log_group.mailer
  id = "/aws/lambda/successfulsuccess-report-mailer"
}

import {
  to = aws_lambda_function.mailer
  id = "successfulsuccess-report-mailer"
}

import {
  to = aws_lambda_permission.mailer_from_s3
  id = "successfulsuccess-report-mailer/successfulsuccess-reports-MailerInvokePermission-cfPaOsRMYRQP"
}

import {
  to = aws_sesv2_email_identity.report
  id = "annadizhak8@gmail.com"
}

# --- reports: the queue and the schedule ---------------------------------------

import {
  to = aws_sqs_queue.requests_dlq
  id = "https://sqs.us-east-1.amazonaws.com/347282156909/successfulsuccess-report-requests-dlq"
}

import {
  to = aws_sqs_queue.requests
  id = "https://sqs.us-east-1.amazonaws.com/347282156909/successfulsuccess-report-requests"
}

import {
  to = aws_lambda_event_source_mapping.requests_to_builder
  id = "c47c9785-9ec7-4ff2-b005-741557523a9f"
}

import {
  to = aws_iam_role.scheduler
  id = "successfulsuccess-reports-SchedulerRole-7s3b1faK95JB"
}

import {
  to = aws_iam_role_policy.scheduler_send
  id = "successfulsuccess-reports-SchedulerRole-7s3b1faK95JB:send-report-requests"
}

import {
  to = aws_scheduler_schedule.weekly
  id = "default/successfulsuccess-weekly-report"
}

# --- ai ------------------------------------------------------------------------

import {
  to = aws_iam_role.parser
  id = "successfulsuccess-ai-ParserRole-kog3MvFVYBlh"
}

import {
  to = aws_iam_role_policy_attachment.parser_basic
  id = "successfulsuccess-ai-ParserRole-kog3MvFVYBlh/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

import {
  to = aws_iam_role_policy.parser_call_claude
  id = "successfulsuccess-ai-ParserRole-kog3MvFVYBlh:call-claude"
}

import {
  to = aws_cloudwatch_log_group.parser
  id = "/aws/lambda/successfulsuccess-agenda-parser"
}

import {
  to = aws_lambda_function.parser
  id = "successfulsuccess-agenda-parser"
}

import {
  to = aws_lambda_function_url.parser
  id = "successfulsuccess-agenda-parser"
}

import {
  to = aws_lambda_permission.parser_url
  id = "successfulsuccess-agenda-parser/successfulsuccess-ai-ParserUrlPermission-LuapNKaaeeVs"
}

import {
  to = aws_lambda_permission.parser_url_invoke
  id = "successfulsuccess-agenda-parser/successfulsuccess-ai-ParserUrlInvokePermission-HnkrXLVRCAfx"
}

import {
  to = aws_budgets_budget.monthly
  id = "347282156909:successfulsuccess-monthly"
}
