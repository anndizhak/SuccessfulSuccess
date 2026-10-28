# Paste an agenda (was infra/ai.yml): a parser function outside the VPC that
# turns pasted text into a suggested agenda with Claude on Amazon Bedrock,
# behind its own function URL. It never writes anything: saving goes through
# the main API.

resource "aws_iam_role" "parser" {
  name = "${var.project_name}-ai-ParserRole-kog3MvFVYBlh"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

}

# Logs only: the function is not in a VPC.
resource "aws_iam_role_policy_attachment" "parser_basic" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# "*" for now, as the lab says; only inference, no model management.
resource "aws_iam_role_policy" "parser_call_claude" {
  name = "call-claude"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "MessagesApiOnBedrock"
        Effect   = "Allow"
        Action   = "bedrock-mantle:CreateInference"
        Resource = "*"
      },
      {
        Sid      = "ConverseApi"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 30
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Turns pasted text into a suggested agenda with Claude on Bedrock"
  package_type  = "Image"
  image_uri     = var.parser_image_uri

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  architectures = [var.architecture]
  role          = aws_iam_role.parser.arn
  memory_size   = 512

  # A parse takes 2-8 s; one retry with the validation error can double it.
  timeout = 30

  # No vpc_config: the parser needs Bedrock and Cognito's public keys on the
  # internet, and no database.
  environment {
    variables = {
      PARSER_API           = var.parser_api
      PARSER_MODEL         = var.parser_model
      BEDROCK_REGION       = local.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.parser.name
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }
}

# Public, like the API's: the handler rejects anyone without a valid Cognito
# access token (401) before any model is called.
resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  cors {
    allow_origins = var.allowed_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}

# The two public-URL permissions, with the statement IDs CloudFormation
# generated, so they are imported and not created twice.
resource "aws_lambda_permission" "parser_url" {
  statement_id           = "${var.project_name}-ai-ParserUrlPermission-LuapNKaaeeVs"
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_url_invoke" {
  statement_id             = "${var.project_name}-ai-ParserUrlInvokePermission-HnkrXLVRCAfx"
  function_name            = aws_lambda_function.parser.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}

# An email when the account's real spend for the month (credits left out)
# reaches 80% and 100% of the budget.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"

  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }
}
