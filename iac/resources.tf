# ---------------------------------------------------------------------------------------------------------------------
# SNS TOPIC
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sns_topic" "event_sns" {
    name = "event-sns"
}

# ---------------------------------------------------------------------------------------------------------------------
# SQS QUEUE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sqs_queue" "event_sqs" {
    name = "event-sqs"
    redrive_policy  = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.event_sqs_dlq.arn}\",\"maxReceiveCount\":5}"
    visibility_timeout_seconds = 300
    kms_master_key_id = aws_kms_key.kms_key.id

    tags = {
        Environment = "dev"
    }
}

resource "aws_sqs_queue" "event_sqs_dlq" {
    name = "event-sqs-dlq"
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS KEY
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_key" "kms_key" {
  description = "kms-key"
}

resource "aws_kms_key_policy" "kms_policy" {
  key_id = aws_kms_key.kms_key.id
  policy = jsonencode({
    Id = "kmsId"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }

        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
    ]
    Version = "2012-10-17"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# SNS SUBSCRIPTION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "event_sqs_target" {
    topic_arn = "${aws_sns_topic.event_sns.arn}"
    protocol  = "sqs"
    endpoint  = "${aws_sqs_queue.event_sqs.arn}"
}

# ---------------------------------------------------------------------------------------------------------------------
# SQS POLICY
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sqs_queue_policy" "event_sqs_policy" {
    queue_url = "${aws_sqs_queue.event_sqs.id}"

    policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.event_sqs.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.event_sns.arn}"
        }
      }
    }
  ]
}
POLICY
}

data "archive_file" "lambda_archive" {
  type = "zip"

  source_dir  = "../EventListenerLambda/src/EventListenerLambda/bin/Release/net6.0/linux-x64/publish"
  output_path = "EventListenerLambda.zip"
}

resource "aws_s3_object" "lambda_bundle" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "EventListenerLambda.zip"
  source = data.archive_file.lambda_archive.output_path

  etag = filemd5(data.archive_file.lambda_archive.output_path)
}

resource "aws_cloudwatch_log_group" "aggregator" {
  name = "/aws/lambda/${aws_lambda_function.function.function_name}"

  retention_in_days = 30
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA FUNCTION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lambda_function" "function" {
  function_name    = "event-listener"
  s3_bucket        = aws_s3_bucket.lambda_bucket.id
  s3_key           = aws_s3_object.lambda_bundle.key
  runtime          = "dotnet6"
  handler          = "EventListenerLambda::EventListenerLambda.Function::FunctionHandler"
  source_code_hash = data.archive_file.lambda_archive.output_base64sha256
  role             = aws_iam_role.lambda_function_role.arn
  timeout          = 30
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA ROLE & POLICIES
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "lambda_function_role" {
  name = "FunctionIamRole_event-listener"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_function_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_role_sqs_policy" {
    name = "AllowSQSPermissions"
    role = "${aws_iam_role.lambda_function_role.name}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage"
      ],
      "Effect": "Allow",
      "Resource": "${aws_sqs_queue.event_sqs.arn}"
    },
    {
       "Action": [
         "kms:Decrypt"
       ],
       "Effect": "Allow",
       "Resource": "${aws_sqs_queue.event_sqs.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_role_logs_policy" {
    name = "LambdaRolePolicy"
    role = "${aws_iam_role.lambda_function_role.name}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:logs:eu-west-1:513702461716:log-group:/aws/lambda/event-listener:*"
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA EVENT SOURCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "event_listener_event_source" {
    event_source_arn = "${aws_sqs_queue.event_sqs.arn}"
    enabled          = true
    function_name    = "${aws_lambda_function.function.arn}"
    batch_size       = 1
}

# ---------------------------------------------------------------------------------------------------------------------
# DynamoDB Table
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "event_storage" {
  name           = "event_storage"
  billing_mode   = "PAY_PER_REQUEST"

  attribute {
    name = "ItemId"
    type = "S"
  }
}

resource "aws_iam_role_policy" "lambda_role_dynamodb_policy" {
  name = "LambdaDynamoDBPolicy"
  role = aws_iam_role.lambda_function_role.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "${aws_dynamodb_table.event_storage.arn}"
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# Kinesis Stream
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kinesis_stream" "kinesis_event_stream" {
  name        = "kinesis_event_stream"
  shard_count = 1
}

resource "aws_dynamodb_kinesis_streaming_destination" "kinesis_event_stream_destination" {
  stream_arn = aws_kinesis_stream.kinesis_event_stream.arn
  table_name = aws_dynamodb_table.event_storage.name
}

# ---------------------------------------------------------------------------------------------------------------------
# Kinesis Data Firehose Delivery Stream
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kinesis_firehose_delivery_stream" "event_delivery_stream" {
  name        = "event_delivery_stream"
  destination = "s3"

  s3_configuration {
    role_arn = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.events_bucket.arn
    prefix    = "events/"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.kinesis_event_stream.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Role for Kinesis Data Firehose
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "firehose_role" {
  name = "KinesisFirehoseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "firehose.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_kinesis_policy" {
  name = "FirehoseKinesisPolicy"
  role = aws_iam_role.firehose_role.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:ListStreams",
        "kms:Decrypt"
      ],
      "Resource": "${aws_kinesis_stream.kinesis_event_stream.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "FirehoseS3Policy"
  role = aws_iam_role.firehose_role.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "${aws_s3_bucket.events_bucket.arn}",
        "${aws_s3_bucket.events_bucket.arn}/*"
      ]
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket 
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "events_bucket" {
  bucket = "cko-project-events-bucket"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "events_bucket_encryption" {
  bucket = aws_s3_bucket.events_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.kms_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket                = "cko-project-lambda-bucket"
  force_destroy         = true
}
