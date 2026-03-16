locals {
  create = merge({
    default    = true
    iam        = true
    kms        = true
    route53    = true
    s3         = true
    cloudtrail = true
    },
    var.basement_create
  )
  env = var.env

  name_prefix  = local.env.name
  account_id   = local.env.account_id
  region       = local.env.region
  region_short = local.env.region_short

  aws_dns_suffix = data.aws_partition.current.dns_suffix
}
