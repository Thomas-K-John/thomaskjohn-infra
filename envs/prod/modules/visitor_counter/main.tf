# DynamoDB Table
resource "aws_dynamodb_table" "visitor_counter" {
  name         = "visitor_counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "visitor_counter_item" {
  table_name = aws_dynamodb_table.visitor_counter.name
  hash_key   = aws_dynamodb_table.visitor_counter.hash_key

  item = <<ITEM
{
  "id": { "S": "visitor_count_id" },
  "visitor_count": { "N": "0" }
}
ITEM
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda_exec_role"
  description        = "IAM role that allows AWS Lambda to assume permissions"
  assume_role_policy = file("${path.module}/policies/lambda-assume-role-policy.json")
}

resource "aws_iam_policy" "cloudwatch_logs_policy" {

  name        = "cloudwatch-logs-policy"
  path        = "/"
  description = "AWS IAM Policy to grant CloudWatch logging permissions"
  policy      = file("${path.module}/policies/cloudwatch-logs-policy.json")
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Resource = aws_dynamodb_table.visitor_counter.arn
      }
    ]
  })
}

# Archive the Lambda function into a ZIP file.
resource "archive_file" "zip_lambda_function" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_function/"
  output_path = "${path.module}/build/visitor_counter.zip"
}

# Create a lambda function
resource "aws_lambda_function" "lambda_function" {
  filename         = archive_file.zip_lambda_function.output_path
  function_name    = "visitor_counter"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "visitor_counter.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120
  source_code_hash = archive_file.zip_lambda_function.output_base64sha256
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }
}


# Create API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "visitor_counter_api"
  description = "API for counting the number of times the website page was viewed"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "api_gateway_resource" {
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "visitor_counter"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

resource "aws_api_gateway_method" "api_gateway_method" {
  resource_id   = aws_api_gateway_resource.api_gateway_resource.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_method" {
  resource_id   = aws_api_gateway_resource.api_gateway_resource.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.api_gateway_resource.id
  http_method = "OPTIONS"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration" "lambda_integration" {
  http_method             = aws_api_gateway_method.api_gateway_method.http_method
  resource_id             = aws_api_gateway_resource.api_gateway_resource.id
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function.invoke_arn
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.api_gateway_resource.id
  http_method             = "OPTIONS"
  type                    = "MOCK"
  integration_http_method = "OPTIONS"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
  depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/GET/visitor_counter"
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api_gateway_resource.id,
      aws_api_gateway_method.api_gateway_method.id,
      aws_api_gateway_integration.lambda_integration.id
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration
  ]
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.api_gateway_resource.id
  http_method = "OPTIONS"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://thomaskjohn.com'"
  }
  response_templates = {
    "application/json" = ""
  }
  depends_on = [
    aws_api_gateway_integration.options_integration
  ]
}

