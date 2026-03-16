resource "aws_acm_certificate" "this" {
  count = local.create.acm ? 1 : 0

  domain_name               = local.route53_zone_name_public
  subject_alternative_names = ["*.${local.route53_zone_name_public}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm" {
  for_each = local.create.acm ? {
    for dvo in aws_acm_certificate.this.*.domain_validation_options[0] : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = local.route53_zone_id_public
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  count = local.create.acm ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.*.arn[0]
  validation_record_fqdns = [for record in aws_route53_record.acm : record.fqdn]
}

locals {
  acm_certificate_arn = try(aws_acm_certificate.this[0].arn, "")
}

output "acm" {
  value = {
    certificate_arn = local.acm_certificate_arn
  }
}
