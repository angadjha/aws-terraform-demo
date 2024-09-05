terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.4.6"
}

provider "aws" {
  region  = "us-east-1"
}

# S3 Bucket
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "buckettfdemo2"
}

# Upload the ZIP file to S3
resource "aws_s3_bucket_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  key    = "demofunction.zip"  # Name of the ZIP file in S3
  source = "demofunction.zip"  # Path to your local ZIP file
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "my_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role     = aws_iam_role.lambda_role.name
}

# Lambda Function
resource "aws_lambda_function" "my_lambda" {
  function_name = "my-go-lambda"

  s3_bucket = aws_s3_bucket.lambda_bucket.bucket
  s3_key    = aws_s3_bucket_object.lambda_zip.key

  handler = "bootstrap"
  runtime = "provided.al2"  # Use Amazon Linux 2 custom runtime

  role = aws_iam_role.lambda_role.arn

  source_code_hash = filebase64sha256("demofunction.zip")  # Compute hash for detecting changes
}

# API Gateway
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "my-api"
  description = "API Gateway for Lambda function"
}

# API Gateway Resource
resource "aws_api_gateway_resource" "my_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part    = "myresource"
}

# API Gateway Method
resource "aws_api_gateway_method" "my_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.my_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "my_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.my_resource.id
  http_method             = aws_api_gateway_method.my_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.my_lambda.arn}/invocations"

  # Enable integration with Lambda
  passthrough_behavior = "WHEN_NO_MATCH"
  content_handling     = "CONVERT_TO_TEXT"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "my_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_integration.my_integration
  ]
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Allow API Gateway to invoke this Lambda function
  source_arn = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/*/*"
}

# Output the API Gateway URL
output "api_url_arn" {
  value = "${aws_api_gateway_rest_api.my_api.execution_arn}/myresource"
  description = "The URL of the API Gateway endpoint"
}

output "api_url" {
  value = "https://${aws_api_gateway_rest_api.my_api.id}.execute-api.us-east-1.amazonaws.com/prod/myresource"
  description = "The URL of the API Gateway endpoint"
}