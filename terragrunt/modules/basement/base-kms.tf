#TODO: move policies to data

locals {
  kms_policy_default = jsonencode({
    Id = "AccessCurrentAccount"
    Statement = [
      {
        Sid    = "Allow key usage from current account"
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = ["arn:aws:iam::${local.account_id}:root"]
        }

        Resource = "*"
      },
      {
        Sid = "AllowEC2AndAutoScalingToUseForEBS"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Effect = "Allow"
        Principal = {
          "Service" : "ec2.amazonaws.com",
          "AWS" : "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          // IAM role must exist, otherwise chicken-egg problem. Dummy ASG with 0 desired capacity can be created once to create the role, then deleted.
        }

        Resource = "*"
      },
    ]
    Version = "2012-10-17"
  })
}

resource "aws_kms_key" "s3" {
  count = local.create.kms ? 1 : 0

  description             = "${local.name_prefix}-s3-${local.region_short}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = local.kms_policy_default // For POC. No need to have ASG role here
}

resource "aws_kms_alias" "s3" {
  count = local.create.kms ? 1 : 0

  name          = "alias/${local.name_prefix}-s3-${local.region_short}"
  target_key_id = aws_kms_key.s3.*.key_id[0]
}

resource "aws_kms_key" "cloudwatch" {
  count = local.create.kms ? 1 : 0

  description             = "${local.name_prefix}-cloudwatch-${local.region_short}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = local.kms_policy_default // For POC. No need to have ASG role here
}

resource "aws_kms_alias" "cloudwatch" {
  count = local.create.kms ? 1 : 0

  name          = "alias/${local.name_prefix}-cloudwatch-${local.region_short}"
  target_key_id = aws_kms_key.cloudwatch.*.key_id[0]
}

resource "aws_kms_key" "ebs" {
  count = local.create.kms ? 1 : 0

  description             = "${local.name_prefix}-ebs-${local.region_short}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = local.kms_policy_default
}

resource "aws_kms_alias" "ebs" {
  count = local.create.kms ? 1 : 0

  name          = "alias/${local.name_prefix}-ebs-${local.region_short}"
  target_key_id = aws_kms_key.ebs.*.key_id[0]
}

resource "aws_ebs_encryption_by_default" "this" {
  count = local.create.kms ? 1 : 0

  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  count = local.create.kms ? 1 : 0

  key_arn = aws_kms_key.ebs[0].arn
}
