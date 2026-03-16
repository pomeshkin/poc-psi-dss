output "s3" {
  value = {
    flow_logs = {
      id  = module.s3_bucket_flow_logs.s3_bucket_id
      arn = module.s3_bucket_flow_logs.s3_bucket_arn
    }
    cloudtrail = {
      id  = module.s3_bucket_cloudtrail.s3_bucket_id
      arn = module.s3_bucket_cloudtrail.s3_bucket_arn
    }
    elb_logs = {
      id  = module.s3_bucket_elb_logs.s3_bucket_id
      arn = module.s3_bucket_elb_logs.s3_bucket_arn
    }
  }
}
