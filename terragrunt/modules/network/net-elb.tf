module "alb_ext" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.0"

  create                     = local.create.elb && local.create.sg
  create_security_group      = false
  enable_deletion_protection = false

  idle_timeout    = 60
  internal        = false
  ip_address_type = "ipv4"

  name    = "${local.name_prefix}-ext"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_groups = aws_security_group.alb_ext.*.id

  access_logs = {
    bucket  = var.network_s3.elb_logs.id
    enabled = local.create.elb_logging
    prefix  = "access-logs"
  }

  connection_logs = {
    bucket  = var.network_s3.elb_logs.id
    enabled = local.create.elb_logging
    prefix  = "connection-logs"
  }

  health_check_logs = {
    bucket  = var.network_s3.elb_logs.id
    enabled = local.create.elb_logging
    prefix  = "health-check-logs"
  }

  listeners = {
    ex-http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    ex-https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = local.acm_certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"

      forward = {
        target_group_key = "ex-app"
      }

      rules = {
        ex-fixed-response = {
          priority = 3
          actions = [{
            fixed_response = {
              content_type = "text/plain"
              status_code  = 200
              message_body = "ALB is ok"
            }
          }]

          conditions = [{
            path_pattern = {
              values = ["/alb-check"]
            }
          }]
        }
      }
    }
  }

  target_groups = {
    ex-app = {
      name                 = "${local.name_prefix}-app"
      protocol             = "HTTPS"
      port                 = 443
      deregistration_delay = 0
      target_type          = "instance"
      vpc_id               = module.vpc.vpc_id
      create_attachment    = false
      health_check = {
        enabled             = true
        interval            = 5
        path                = "/healthz"
        port                = "traffic-port"
        healthy_threshold   = 5
        unhealthy_threshold = 2
        timeout             = 3
        protocol            = "HTTPS"
        matcher             = "200-399"
      }
    }
  }

  tags = {}
}

resource "aws_route53_record" "alb_ext" {
  count = local.create.elb ? 1 : 0

  zone_id = local.route53_zone_id_public
  name    = local.route53_zone_name_public
  type    = "A"

  alias {
    name                   = module.alb_ext.dns_name
    zone_id                = module.alb_ext.zone_id
    evaluate_target_health = true
  }
}
