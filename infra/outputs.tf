# Everything the Makefile and the frontend build read (`terraform output -raw`).

# auth
output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  description = "Public OAuth client ID (safe to ship in the frontend build)"
  value       = aws_cognito_user_pool_client.web.id
}

output "authority" {
  description = "OIDC issuer the frontend signs in against"
  value       = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "cognito_domain" {
  description = "Managed login and logout endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  description = "Authorised redirect URI to register on the Google OAuth client"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com/oauth2/idpresponse"
}

# reports
output "bucket_name" {
  value = aws_s3_bucket.reports.id
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "builder_function_name" {
  value = aws_lambda_function.builder.function_name
}

output "builder_log_group" {
  value = aws_cloudwatch_log_group.builder.name
}

output "schedule_name" {
  value = aws_scheduler_schedule.weekly.name
}

output "request_queue_url" {
  value = aws_sqs_queue.requests.url
}

output "dead_letter_queue_url" {
  value = aws_sqs_queue.requests_dlq.url
}

output "mailer_function_name" {
  value = aws_lambda_function.mailer.function_name
}

output "mailer_log_group" {
  value = aws_cloudwatch_log_group.mailer.name
}

# ai
output "parser_url" {
  description = "The parser's endpoint (POST), without the trailing slash"
  value       = trimsuffix(aws_lambda_function_url.parser.function_url, "/")
}

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}

output "parser_log_group" {
  value = aws_cloudwatch_log_group.parser.name
}
