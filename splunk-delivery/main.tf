# get any data required
data "aws_caller_identity" "this" {}
data "aws_region" "this" {}

# locals
locals {
  lambda_name       = "lambda-cw-transform"
  account_id        = data.aws_caller_identity.this.account_id
  region            = data.aws_region.this.name
}

# create iam role for firehose lambda function
resource "aws_iam_role" "lambda" {
  name               = join("-", [var.prefix, "lambda"])
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# lambda iam policy
resource "aws_iam_role_policy" "lambda" {
  name   = join("-", [var.prefix, "lambda"])
  role   = aws_iam_role.lambda.name
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

# lambda
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/${local.lambda_name}/"
  output_path = "${path.module}/lambda/${local.lambda_name}.zip"
}

resource "aws_lambda_function" "this" {
  function_name    = join("-", [var.prefix, local.lambda_name])
  description      = "lambda for splunk streaming"
  role             = aws_iam_role.lambda.arn
  memory_size      = var.memory_size
  runtime          = var.nodejs_runtime
  timeout          = var.timeout
  handler          = "lambda-cw-transform.handler"
  filename         = "${path.module}/lambda/${local.lambda_name}.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}

# create iam role for firehose lambda function
resource "aws_iam_role" "firehose" {
  name               = join("-", [var.prefix, "firehose"])
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# firehose iam policy
resource "aws_iam_role_policy" "firehose" {
  name   = join("-", [var.prefix, "firehose"])
  role   = aws_iam_role.lambda.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${aws_s3_bucket.failures.id}",
        "arn:aws:s3:::${aws_s3_bucket.failures.id}/*"
      ]
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "lambda:GetFunctionConfiguration"
      ],
      "Resource": "arn:aws:lambda:${local.region}:${local.account_id}:function:${aws_lambda_function.this.function_name}:$LATEST"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents"
      ],
      "Resource": [
        ${aws_cloudwatch_log_group.kinesis_logs.arn},
        ${aws_cloudwatch_log_stream.kinesis_logs.arn}
      ]
    }
  ]
}
EOF
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = join("-",[var.prefix,"splunk-delivery-stream"])
  destination = "splunk"

  s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    prefix             = var.s3_prefix
    bucket_arn         = aws_s3_bucket.failures.arn
    buffer_size        = var.kinesis_firehose_buffer
    buffer_interval    = var.kinesis_firehose_buffer_interval
    compression_format = var.s3_compression_format
  }

  splunk_configuration {
    hec_endpoint               = var.splunk_hec_url
    hec_token                  = var.splunk_hec_token
    hec_acknowledgment_timeout = var.hec_acknowledgment_timeout
    hec_endpoint_type          = var.hec_endpoint_type
    s3_backup_mode             = var.s3_backup_mode

    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.this.arn}:$LATEST"
        }
        parameters {
          parameter_name  = "RoleArn"
          parameter_value = aws_iam_role.firehose.arn
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = var.enable_fh_cloudwatch_logging
      log_group_name  = aws_cloudwatch_log_group.kinesis_logs.name
      log_stream_name = aws_cloudwatch_log_stream.kinesis_logs.name
    }
  }

  tags = var.tags
}

# error bucket
resource "aws_s3_bucket" "failures" {
  bucket_prefix  = join("-", [var.prefix, "delivery-failures-"])

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = var.tags
}

# cloudwatch logging group for firehose
resource "aws_cloudwatch_log_group" "kinesis_logs" {
  name              = "/aws/kinesisfirehose/${join("-",[var.prefix,"splunk-delivery-stream"])}"
  retention_in_days = var.cloudwatch_log_retention

  tags = var.tags
}

# stream for firehose logs
resource "aws_cloudwatch_log_stream" "kinesis_logs" {
  name           = join("-",[var.prefix,"kinesis-log-stream"])
  log_group_name = aws_cloudwatch_log_group.kinesis_logs.name
}

# create iam role for cw destination
resource "aws_iam_role" "cw" {
  name               = join("-", [var.prefix, "cw"])
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# cw destination iam policy
resource "aws_iam_role_policy" "cw" {
  name   = join("-", [var.prefix, "cw"])
  role   = aws_iam_role.cw.name
  policy = <<EOF
{
    "Statement":[
      {
        "Effect":"Allow",
        "Action":["firehose:*"],
        "Resource":["${aws_kinesis_firehose_delivery_stream.this.arn}"]
      },
      {
        "Effect":"Allow",
        "Action":["iam:PassRole"],
        "Resource":["arn:aws:iam::${aws_iam_role.cw.arn}"]
      }
    ]
}
EOF
}

resource "aws_cloudwatch_log_destination" "this" {
  name       = join("-", [var.prefix, "splunk-logs-destination"])
  role_arn   = aws_iam_role.cw.arn
  target_arn = aws_kinesis_firehose_delivery_stream.this.arn
}

data "aws_iam_policy_document" "destination_policy" {
  statement {
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.sender_account_ids
    }

    actions = [
      "logs:PutSubscriptionFilter",
    ]

    resources = [
      aws_cloudwatch_log_destination.this.arn
    ]
  }
}

resource "aws_cloudwatch_log_destination_policy" "this" {
  destination_name = aws_cloudwatch_log_destination.this.name
  access_policy    = data.aws_iam_policy_document.destination_policy.json

  lifecycle {
    ignore_changes = [access_policy]
  }
}
