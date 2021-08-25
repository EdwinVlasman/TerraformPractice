provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      Application = "delivery-period-service"
    }
  }
}

# Data

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "subscription-created-event-queue-policy-document" {
  statement {
    sid    = "Allow SNS delivery subscription topic to send message"
    effect = "Allow"
    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.subscription-created-event-queue.arn]
    condition {
      test     = "ArnLike"
      values   = ["arn:aws:sns:eu-central-1:${data.aws_caller_identity.current.account_id}:delivery-subscription-topic"]
      variable = "aws:SourceArn"
    }
  }
}

data "aws_iam_policy_document" "subscription-created-event-queue-dead-letter-policy-document" {
  statement {
    sid    = "Allow sns topic to send message"
    effect = "Allow"
    principals {
      identifiers = [
        "*"
      ]
      type = "AWS"
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.subscription-created-event-queue-dead-letter.arn]
    condition {
      test = "ArnEquals"
      values = [
        "arn:aws:sns:eu-central-1:${data.aws_caller_identity.current.account_id}:delivery-subscription-topic",
        aws_sqs_queue.subscription-created-event-queue.arn
      ]
      variable = "aws:SourceArn"
    }
  }
}

# Resources

resource "aws_sqs_queue" "subscription-created-event-queue" {
  name                      = "subscription-created-event-queue"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.subscription-created-event-queue-dead-letter.arn
    maxReceiveCount     = 4
  })
  kms_master_key_id = "alias/sns-delivery-subscription_key"
  tags = {
    Service = "Delivery-period"
  }
}

resource "aws_sqs_queue_policy" "subscription-created-event-queue-policy" {
  queue_url = aws_sqs_queue.subscription-created-event-queue.id
  policy    = data.aws_iam_policy_document.subscription-created-event-queue-policy-document.json
}

resource "aws_sqs_queue" "subscription-created-event-queue-dead-letter" {
  name                      = "subscription-created-event-queue-dead-letter"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/sns-delivery-subscription_key"
  tags = {
    Service = "Delivery-period"
  }
}

resource "aws_sqs_queue_policy" "subscription-created-event-queue-dead-letter-policy" {
  queue_url = aws_sqs_queue.subscription-created-event-queue-dead-letter.id
  policy    = data.aws_iam_policy_document.subscription-created-event-queue-dead-letter-policy-document.json
}

resource "aws_sns_topic_subscription" "subscription-created-event-subscription" {
  endpoint  = aws_sqs_queue.subscription-created-event-queue.arn
  protocol  = "sqs"
  topic_arn = "arn:aws:sns:eu-central-1:${data.aws_caller_identity.current.account_id}:delivery-subscription-topic"
  filter_policy = jsonencode({
    "eventType" : ["DELIVERY_SUBSCRIPTION_CREATED"],
    "version" : ["V1"]
  })
  redrive_policy = jsonencode({
    "deadLetterTargetArn" : aws_sqs_queue.subscription-created-event-queue-dead-letter.arn
  })
}

# This block is normally created inside delivery subscription service

resource "aws_kms_key" "delivery-subscription" {
  description         = "sns-encrypted-usage-kms"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.key_policy.json
  tags = {Service = "Delivery-period"}
}

data "aws_iam_policy_document" "key_policy" {
  statement {
    sid       = "Enable IAM User Permissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "Allow key-usage for SNS and SQS"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"]
    principals {
      type = "Service"
      identifiers = [
        "sns.amazonaws.com",
      "sqs.amazonaws.com"]
    }
  }
}

resource "aws_kms_alias" "delivery-subscription_alias" {
  name          = "alias/sns-delivery-subscription_key"
  target_key_id = aws_kms_key.delivery-subscription.key_id
}

resource "aws_sns_topic" "delivery-subscription" {
  name              = "delivery-subscription-topic"
  kms_master_key_id = "alias/sns-delivery-subscription_key"
  tags = {Service = "Delivery-period"}
}

resource "aws_sqs_queue" "import-test-queue" {
  name                      = "import-test-que"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/sns-delivery-subscription_key"
  tags = {
    Service = "Delivery-period"
  }
}
