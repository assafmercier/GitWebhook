terraform {  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

provider "github" {
  #organization = "myorgname"
  token        = "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"
}

resource "aws_api_gateway_rest_api" "git_webhook_api" {
  name = "git_webhook_api"
  description = "My Webhook API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.git_webhook_api.id
  parent_id = aws_api_gateway_rest_api.git_webhook_api.root_resource_id
  path_part = "mypath"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.git_webhook_api.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.git_webhook_api.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type = "AWS"
  uri = aws_lambda_function.webhook_lambda.invoke_arn
}

resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.git_webhook_api.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"

  //cors section
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.git_webhook_api.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.proxy.status_code

  //cors
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" =  "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.lambda_integration
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    #aws_api_gateway_integration.options_integration, # Add this line
  ]

  rest_api_id = aws_api_gateway_rest_api.git_webhook_api.id
  stage_name = "dev"
}

data "archive_file" "lambda_package" {
  type = "zip"
  source_file = "index.js"
  output_path = "index.zip"
}
resource "aws_lambda_function" "webhook_lambda" {
  filename = "index.zip"
  function_name = "myWebhookLambdaFunction"
  role = aws_iam_role.lambda_role.arn
  handler = "index.handler"
  runtime = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
    {
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }
  ]
})
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role = aws_iam_role.lambda_role.name
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id = "AllowExecutionFromAPIGateway"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_lambda.function_name
  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.git_webhook_api.execution_arn}/*/*/*"
}

# resource "aws_cloudwatch_log_group" "lambda-webhook" {
#   name = "/aws/lambda/${aws_lambda_function.webhook_lambda.function_name}"
#   retention_in_days = 3
# } 

resource "github_repository" "repo" {
  name         = "GitWebhook"
  description  = "GitWebhook demo"
  #homepage_url = "https://github.com/assafmercier/GitWebhook/"

  visibility   = "public"
}

resource "github_repository_webhook" "foo" {
  repository = github_repository.repo.name

  configuration {
    #url          = "https://google.de/"
    url           = "${aws_api_gateway_deployment.deployment.invoke_url}${aws_api_gateway_deployment.deployment.stage_name}${aws_api_gateway_resource.webhook.path}"
    #url          = "${aws_api_gateway_deployment.this.invoke_url}${aws_api_gateway_stage.this.stage_name}${aws_api_gateway_resource.this.path}"
    content_type = "form"
    insecure_ssl = false
  }

  active = true

  events = ["push"]
}