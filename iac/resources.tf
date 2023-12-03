resource "aws_sns_topic" "event_sns" {
    name = "event-sns"
}

resource "aws_sqs_queue" "event_sqs" {
    name = "event-sqs"
    redrive_policy  = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.event_sqs_dlq.arn}\",\"maxReceiveCount\":5}"
    visibility_timeout_seconds = 300

    tags = {
        Environment = "dev"
    }
}

resource "aws_sqs_queue" "event_sqs_dlq" {
    name = "event-sqs-dlq"
}

resource "aws_sns_topic_subscription" "event_sqs_target" {
    topic_arn = "${aws_sns_topic.event_sns.arn}"
    protocol  = "sqs"
    endpoint  = "${aws_sqs_queue.event_sqs.arn}"
}

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
