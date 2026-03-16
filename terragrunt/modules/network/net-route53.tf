locals {
  // Create Route53 zone for internal endpoints
  route53_zone_name_private = "${local.name_prefix}.${local.region}.local"
}

resource "aws_route53_zone" "private" {
  count = local.create.route53 && local.create.vpc ? 1 : 0

  name = local.route53_zone_name_private
  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_route53_resolver_firewall_domain_list" "allowed" {
  count = local.create.route53_firewall && local.create.vpc ? 1 : 0

  name    = "${local.name_prefix}-allowed"
  domains = ["example.com.", "secureweb.com.", "*.${local.region}.amazonaws.com."]
}

resource "aws_route53_resolver_firewall_domain_list" "blocked" {
  count = local.create.route53_firewall && local.create.vpc ? 1 : 0

  name    = "${local.name_prefix}-blocked"
  domains = ["*."]
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  count = local.create.route53_firewall && local.create.vpc ? 1 : 0

  name = local.name_prefix
}

resource "aws_route53_resolver_firewall_rule_group_association" "this" {
  count = local.create.route53_firewall && local.create.vpc ? 1 : 0

  name                   = local.name_prefix
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.this[0].id
  priority               = 101 // 100 is reserved by AWS
  vpc_id                 = module.vpc.vpc_id
}

resource "aws_route53_resolver_firewall_rule" "allowed" {
  count = local.create.route53_firewall && local.create.vpc ? 1 : 0

  name                    = "${local.name_prefix}-allowed"
  action                  = "ALLOW"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.allowed[0].id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this[0].id
  priority                = 100
}

resource "aws_route53_resolver_firewall_rule" "blocked" {
  count = local.create.route53_firewall && local.create.vpc ? 1 : 0

  name                    = "${local.name_prefix}-blocked"
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.blocked[0].id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this[0].id
  priority                = 101
}

output "route53" {
  value = {
    zone_id_private   = local.route53_zone_id_private
    zone_name_private = local.route53_zone_name_private
    zone_id_public    = local.route53_zone_id_public
    zone_name_public  = local.route53_zone_name_public
  }
}
