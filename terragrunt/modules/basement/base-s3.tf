module "s3_bucket_flow_logs" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.10"

  create_bucket = local.create.s3

  bucket        = "${local.name_prefix}-logs-vpc-flow-logs-${local.region_short}-${local.account_id}"
  force_destroy = true

  # Policy works for flow logs as well
  attach_waf_log_delivery_policy = true

  server_side_encryption_configuration = local.create.kms ? {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3[0].arn
      }
    }
  } : {}
  versioning = {
    enabled = true
  }
  //policy = null
}

locals {
  s3_bucket_name_cloudtrail = "${local.name_prefix}-logs-cloudtrail-${local.region_short}-${local.account_id}"
  s3_bucket_arn_cloudtrail  = "arn:${data.aws_partition.current.partition}:s3:::${local.s3_bucket_name_cloudtrail}"
}

module "s3_bucket_cloudtrail" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.10"

  create_bucket = local.create.s3

  bucket        = local.s3_bucket_name_cloudtrail
  force_destroy = true

  server_side_encryption_configuration = local.create.kms ? {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3[0].arn
      }
    }
  } : {}
  versioning = {
    enabled = true
  }
  // https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-s3-bucket-policy-for-cloudtrail.html
  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = local.s3_bucket_arn_cloudtrail
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.cloudtrail_arn
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:PutObject"

        Resource = "${local.s3_bucket_arn_cloudtrail}/AWSLogs/${local.account_id}/*"

        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.cloudtrail_arn
          }
        }
      }
    ]
  })
}

locals {
  s3_bucket_name_elb_logs = "${local.name_prefix}-logs-elb-${local.region_short}-${local.account_id}"
  s3_bucket_arn_elb_logs  = "arn:${data.aws_partition.current.partition}:s3:::${local.s3_bucket_name_elb_logs}"
}

module "s3_bucket_elb_logs" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.10"

  create_bucket = local.create.s3

  bucket        = local.s3_bucket_name_elb_logs
  force_destroy = true

  acl = "log-delivery-write"

  server_side_encryption_configuration = local.create.kms ? {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3[0].arn
      }
    }
  } : {}
  versioning = {
    enabled = true
  }

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  // https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html#attach-bucket-policy
  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ELBLogs"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${local.s3_bucket_arn_elb_logs}/*/AWSLogs/${local.account_id}/*"
      },
    ]
  })
}
