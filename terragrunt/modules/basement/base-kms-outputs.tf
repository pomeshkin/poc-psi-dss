output "kms" {
  value = {
    keys = {
      ebs = {
        target_key_arn = concat(aws_kms_alias.ebs.*.target_key_arn, [""])[0]
        alias_arn      = concat(aws_kms_alias.ebs.*.arn, [""])[0]
      }
      s3 = {
        target_key_arn = concat(aws_kms_alias.s3.*.target_key_arn, [""])[0]
        alias_arn      = concat(aws_kms_alias.s3.*.arn, [""])[0]
      }
      cloudwatch = {
        target_key_arn = concat(aws_kms_alias.cloudwatch.*.target_key_arn, [""])[0]
        alias_arn      = concat(aws_kms_alias.cloudwatch.*.arn, [""])[0]
      }
    }
  }
}
