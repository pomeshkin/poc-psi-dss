locals {
  create = merge({
    default            = true
    acm                = true
    elb                = true
    elb_logging        = false // TODO: enable for PCI DSS. Doesn't work, need to fix bucket policy. InvalidConfigurationRequest: Access Denied for bucket: dev-logs-elb-use2-533267016219. Please check S3bucket permission
    route53            = true
    route53_firewall   = true
    sg                 = true
    vpc                = true
    vpc_nat_gw         = true
    vpc_flow_log       = true
    vpc_endpoints      = true
    vpc_dedicated_acls = true
    },
    var.network_create
  )

  env = var.env

  name_prefix  = local.env.name
  account_id   = local.env.account_id
  region       = local.env.region
  region_short = local.env.region_short

  route53                  = var.network_route53
  route53_zone_id_public   = local.route53.zone_id_public
  route53_zone_name_public = local.route53.zone_name_public
  route53_zone_id_private  = try(aws_route53_zone.private[0].id, "")
}
