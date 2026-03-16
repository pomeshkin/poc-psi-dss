locals {
  create = merge({
    default   = true
    ec2_mysql = true
    asg_app   = true
    },
    var.compute_create
  )

  env = var.env

  name_prefix  = local.env.name
  account_id   = local.env.account_id
  region       = local.env.region
  region_short = local.env.region_short
}
