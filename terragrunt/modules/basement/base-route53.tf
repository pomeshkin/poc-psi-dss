resource "aws_route53_zone" "public" {
  count = local.create.route53 && var.basement_route53_zone_name_public != "" ? 1 : 0

  name = var.basement_route53_zone_name_public
}

output "route53" {
  value = {
    zone_id_public           = concat(aws_route53_zone.public.*.zone_id, [""])[0]
    zone_name_public         = var.basement_route53_zone_name_public
    zone_name_servers_public = concat(aws_route53_zone.public.*.name_servers, [""])[0]
  }
}
