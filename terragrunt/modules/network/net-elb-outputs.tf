output "alb_ext" {
  value = {
    id              = module.alb_ext.id
    arn             = module.alb_ext.arn
    arn_suffix      = module.alb_ext.arn_suffix
    dns_name        = module.alb_ext.dns_name
    zone_id         = module.alb_ext.zone_id
    target_groups   = module.alb_ext.target_groups
    dns_name_custom = try(aws_route53_record.alb_ext[0].name, "")
  }
}
