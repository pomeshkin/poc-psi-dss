locals {
  cloudtrail_name = "${local.name_prefix}-organization-trail"
  cloudtrail_arn  = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${local.cloudtrail_name}"
}

resource "aws_cloudtrail" "this" {
  count = local.create.cloudtrail ? 1 : 0

  name           = local.cloudtrail_name
  s3_bucket_name = module.s3_bucket_cloudtrail.s3_bucket_id
  //s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}
