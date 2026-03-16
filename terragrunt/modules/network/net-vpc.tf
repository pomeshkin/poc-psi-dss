locals {
  public_inbound_ports = [80, 443]

  network_acls = {
    public_inbound = concat(
      [
        {
          rule_number = 100
          rule_action = "allow"
          from_port   = 1024
          to_port     = 65535
          protocol    = "tcp"
          cidr_block  = "0.0.0.0/0"
        },
      ],
      flatten([
        for cidr_idx, cidr in var.network_allowed_cidrs_ingress : [
          for port_idx, port in local.public_inbound_ports : {
            rule_number = 110 + (cidr_idx * length(local.public_inbound_ports) + port_idx) * 10
            rule_action = "allow"
            from_port   = port
            to_port     = port
            protocol    = "tcp"
            cidr_block  = cidr
          }
        ]
      ])
    )
    public_outbound = concat(
      [
        {
          rule_number = 100
          rule_action = "allow"
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_block  = "0.0.0.0/0"
        },
      ],
      [
        for idx, cidr in var.network_allowed_cidrs_ingress : {
          rule_number = 110 + idx * 10
          rule_action = "allow"
          from_port   = 1024
          to_port     = 65535
          protocol    = "tcp"
          cidr_block  = cidr
        }
      ]
    )
    //
    private_inbound = concat(
      [ // To app and VPCe
        for idx, cidr in concat(var.network_vpc_public_subnets, var.network_vpc_database_subnets) : {
          rule_number = 100 + idx * 10
          rule_action = "allow"
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_block  = cidr
        }
      ],
      [
        {
          rule_number = 200
          rule_action = "allow"
          from_port   = 1024
          to_port     = 65535
          protocol    = "tcp"
          cidr_block  = "0.0.0.0/0"
        },
      ],
      // [ // Return from database
      //   for idx, cidr in var.network_vpc_database_subnets : {
      //     rule_number = 200 + idx * 10
      //     rule_action = "allow"
      //     from_port   = 1024
      //     to_port     = 65535
      //     protocol    = "tcp"
      //     cidr_block  = cidr
      //   }
      // ],
    )
    private_outbound = concat(
      [
        {
          rule_number = 100
          rule_action = "allow"
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_block  = "0.0.0.0/0"
        },
      ],
      [
        for idx, cidr in concat(var.network_vpc_public_subnets, var.network_vpc_database_subnets) : {
          rule_number = 110 + idx * 10
          rule_action = "allow"
          from_port   = 1024
          to_port     = 65535
          protocol    = "tcp"
          cidr_block  = cidr
        }
      ],
      // [
      //   for idx, cidr in var.network_vpc_database_subnets : {
      //     rule_number = 200 + idx * 10
      //     rule_action = "allow"
      //     from_port   = 3306
      //     to_port     = 3306
      //     protocol    = "tcp"
      //     cidr_block  = cidr
      //   }
      // ],
    )
    database_inbound = concat(
      [
        for idx, cidr in var.network_vpc_private_subnets : {
          rule_number = 100 + idx * 10
          rule_action = "allow"
          from_port   = 1024
          to_port     = 65535
          protocol    = "tcp"
          cidr_block  = cidr
        }
      ],
    )
    database_outbound = concat(
      [
        for idx, cidr in var.network_vpc_private_subnets : {
          rule_number = 100 + idx * 10
          rule_action = "allow"
          from_port   = 1024
          to_port     = 65535
          protocol    = "tcp"
          cidr_block  = cidr
        }
      ],
      [
        for idx, cidr in var.network_vpc_private_subnets : {
          rule_number = 200 + idx * 10
          rule_action = "allow"
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_block  = cidr
        }
      ],
    )
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  create_vpc           = local.create.vpc
  name                 = local.name_prefix
  cidr                 = var.network_vpc_cidr
  azs                  = var.network_vpc_azs
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnets   = var.network_vpc_public_subnets
  private_subnets  = var.network_vpc_private_subnets
  database_subnets = var.network_vpc_database_subnets

  map_public_ip_on_launch = true

  enable_nat_gateway     = local.create.vpc_nat_gw // Regional NAT Gateway should be used, but module does not support it yet
  single_nat_gateway     = !var.env.is_prod
  one_nat_gateway_per_az = var.env.is_prod

  public_dedicated_network_acl = local.create.vpc_dedicated_acls
  public_inbound_acl_rules     = local.network_acls["public_inbound"]
  public_outbound_acl_rules    = local.network_acls["public_outbound"]

  private_dedicated_network_acl = local.create.vpc_dedicated_acls
  private_inbound_acl_rules     = local.network_acls["private_inbound"]
  private_outbound_acl_rules    = local.network_acls["private_outbound"]

  database_dedicated_network_acl = local.create.vpc_dedicated_acls
  database_inbound_acl_rules     = local.network_acls["database_inbound"]
  database_outbound_acl_rules    = local.network_acls["database_outbound"]
}

module "flow_log_s3" {
  source  = "terraform-aws-modules/vpc/aws//modules/flow-log"
  version = "6.6.0"

  create = local.create.vpc_flow_log && local.create.vpc

  name   = "${local.name_prefix}-s3"
  vpc_id = module.vpc.vpc_id

  log_destination_type = "s3"
  log_destination      = var.network_s3.flow_logs.arn
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.0"

  create = local.create.vpc_endpoints && local.create.vpc

  vpc_id = module.vpc.vpc_id

  create_security_group = false
  security_group_ids    = aws_security_group.vpc_endpoints.*.id

  endpoints = {
    s3 = {
      service             = "s3"
      private_dns_enabled = true
      dns_options = {
        private_dns_only_for_inbound_resolver_endpoint = false
      }
    },
    kms = {
      service             = "kms"
      private_dns_enabled = true
      subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
      security_group_ids  = aws_security_group.vpc_endpoints.*.id
    },
    // ec2 = {
    //   service             = "ec2"
    //   private_dns_enabled = true
    //   subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
    //   security_group_ids  = aws_security_group.vpc_endpoints.*.id
    // },
    // logs = {
    //   service             = "logs"
    //   private_dns_enabled = true
    //   subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
    //   security_group_ids  = aws_security_group.vpc_endpoints.*.id
    // },
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
      security_group_ids  = aws_security_group.vpc_endpoints.*.id
    },
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
      security_group_ids  = aws_security_group.vpc_endpoints.*.id
    },
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
      security_group_ids  = aws_security_group.vpc_endpoints.*.id
    },
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
      security_group_ids  = aws_security_group.vpc_endpoints.*.id
    },
    secretsmanager = {
      service             = "secretsmanager"
      private_dns_enabled = true
      subnet_ids          = local.env.is_prod ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
      security_group_ids  = aws_security_group.vpc_endpoints.*.id
    },
  }
}

output "vpc" {
  value = {
    id                       = module.vpc.vpc_id
    cidr                     = module.vpc.vpc_cidr_block
    azs                      = module.vpc.azs
    public_subnets           = module.vpc.public_subnets
    private_subnets          = module.vpc.private_subnets
    database_subnets         = module.vpc.database_subnets
    private_route_table_ids  = module.vpc.private_route_table_ids
    public_route_table_ids   = module.vpc.public_route_table_ids
    database_route_table_ids = module.vpc.database_route_table_ids
  }
}
