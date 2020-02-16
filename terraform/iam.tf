resource "aws_iam_role" "web_server_role" {
  name               = "WebServerRole"
  description        = "Web server role"
  assume_role_policy = data.aws_iam_policy_document.web_server_trust_policy.json
}

data "aws_iam_policy_document" "web_server_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "rds_attachment" {
  policy_arn = aws_iam_policy.rds_policy.arn
  role       = aws_iam_role.web_server_role.id
}

resource "aws_iam_role_policy_attachment" "ssm_attachment" {
  policy_arn = aws_iam_policy.ssm_policy.arn
  role       = aws_iam_role.web_server_role.id
}

resource "aws_iam_role_policy_attachment" "s3_attachment" {
  policy_arn = aws_iam_policy.s3_policy.arn
  role       = aws_iam_role.web_server_role.id
}

resource "aws_iam_policy" "rds_policy" {
  name        = "GhostWebServerRDSPolicy"
  description = "Allow describe RDS instance and list tags"
  policy      = data.aws_iam_policy_document.rds_policy_document.json
}

resource "aws_iam_policy" "ssm_policy" {
  name        = "GhostWebServerSSMPolicy"
  description = "Allow get parameters and use KMS keys"
  policy      = data.aws_iam_policy_document.ssm_policy_document.json
}

resource "aws_iam_policy" "s3_policy" {
  name        = "GhostWebServerS3Policy"
  description = "Policy for s3 sync task"
  policy      = data.aws_iam_policy_document.s3_policy_document.json
}

data "aws_iam_policy_document" "rds_policy_document" {
  statement {
    actions = [
      "rds:DescribeDBInstances",
      "rds:ListTagsForResource",
    ]

    effect = "Allow"

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "ssm_policy_document" {
  statement {
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
      "ssm:DescribeParameters",
      "kms:decrypt",
      "kms:DescribeKey",
      "kms:encrypt",
    ]

    effect = "Allow"

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "s3_policy_document" {
  statement {
    actions = [
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]

    effect = "Allow"

    resources = ["*"]
  }
}

