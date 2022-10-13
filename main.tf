terraform {
  backend "remote" {
    organization = "chxnedu-crc"

    workspaces {
      name = "Prod-Env-Backend"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "VisitorCount" {
  name = "VisitorCounterDB"
  hash_key = "Version"
  attribute {
    name = "Version"
    type = "N"
  }
  billing_mode = "PROVISIONED"
  read_capacity = 1
  write_capacity = 1
}

resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "table/${aws_dynamodb_table.VisitorCount.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }

    target_value = 70
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "table/${aws_dynamodb_table.VisitorCount.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_write_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }

    target_value = 70
  }
}

resource "aws_dynamodb_table_item" "Count" {
  table_name = aws_dynamodb_table.VisitorCount.name
  hash_key = aws_dynamodb_table.VisitorCount.hash_key
  item = <<-EOS
  {
  "Version": { "N": "1" },
  "TotalCount": { "N": "0" }
}
EOS
  lifecycle {
    ignore_changes = [
      item,
    ]
  }
}

resource "aws_iam_role" "lambda_role" {
name   = "Visitor_Count_Lambda_Role"
assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

data "aws_iam_policy" "BasicExecutionRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy" "DynamodbFullAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "attach_role_to_policy" {
  role = aws_iam_role.lambda_role.name
  policy_arn = data.aws_iam_policy.BasicExecutionRole.arn
}

resource "aws_iam_role_policy_attachment" "attach_dynamo_role_to_policy" {
  role = aws_iam_role.lambda_role.name
  policy_arn = data.aws_iam_policy.DynamodbFullAccess.arn
}

data "archive_file" "zip_the_code" {
  type = "zip"
  source_dir = "${path.module}/python/"
  output_path = "${path.module}/python/lambda_python.zip"
}

resource "aws_lambda_function" "UpdateVisitorCount" {
  function_name = "UpdateCount"
  role = aws_iam_role.lambda_role.arn
  architectures = ["x86_64"]
  filename = "${path.module}/python/lambda_python.zip"
  handler = "lambda_code.update"
  runtime = "python3.9"

  depends_on = [
    aws_dynamodb_table_item.Count,
    aws_iam_role_policy_attachment.attach_role_to_policy,
    aws_iam_role_policy_attachment.attach_dynamo_role_to_policy
  ]
}

resource "aws_lambda_permission" "lambda-permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.UpdateVisitorCount.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.crc-api.execution_arn}/*/*/update_count"
}

resource "aws_apigatewayv2_api" "crc-api" {
  name = "CRC-API"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["https://resume.chxnedu.com"]
  }

  depends_on = [
    aws_lambda_function.UpdateVisitorCount
  ]
}

resource "aws_apigatewayv2_integration" "lambda-integration" {
  api_id = aws_apigatewayv2_api.crc-api.id
  integration_type = "AWS_PROXY"

  connection_type = "INTERNET"
  description = "Integrating my lambda function to API"
  integration_method = "POST"
  integration_uri = aws_lambda_function.UpdateVisitorCount.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda-route" {
  api_id    = aws_apigatewayv2_api.crc-api.id
  route_key = "ANY /update_count"
  target = "integrations/${aws_apigatewayv2_integration.lambda-integration.id}"
}

resource "aws_apigatewayv2_stage" "lambda-stage" {
  api_id = aws_apigatewayv2_api.crc-api.id
  name   = "$default"
  auto_deploy = true
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.crc-api.api_endpoint
}

resource "aws_sns_topic" "lambda_alert" {
  name = "LAMBDA_ALERT"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.lambda_alert.arn
  protocol = "email"
  endpoint = "ojichinedu4@gmail.com"
}

resource "aws_cloudwatch_metric_alarm" "lambda_error" {
  alarm_name = "LAMBDA_ERROR"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "5"
  metric_name = "Errors"
  namespace = "AWS/Lambda"
  period = "300"
  statistic = "Average"
  threshold = "1"
  actions_enabled = true
  alarm_actions = [ aws_sns_topic.lambda_alert.arn ]
  alarm_description = "Alerts me when Lambda has an error"
}