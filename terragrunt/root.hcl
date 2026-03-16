inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  {
    env = {
      name                     = local.env
      account_id               = local.account_id
      account_name             = local.account_name
      region                   = local.aws_region
      region_short             = local.aws_region_short
      route53_zone_name_public = local.route53_zone_name_public
      #
      layer = local.layer
      #
      is_prod = local.is_prod
    },
    #
    basement_route53_zone_name_public = local.route53_zone_name_public
    #
    network_vpc_cidr              = local.network_vpc_cidr
    network_vpc_azs               = formatlist("${local.aws_region}%s", local.aws_regions[local.aws_region]["azs"])
    network_vpc_public_subnets    = local.network_vpc_public_subnets
    network_vpc_private_subnets   = local.network_vpc_private_subnets
    network_vpc_database_subnets  = local.network_vpc_database_subnets
    network_allowed_cidrs_ingress = ["0.0.0.0/1", "128.0.0.0/1"] // Dummy allowed IP ranges
    #
    default_tags   = local.default_tags
    terragrunt_dir = get_repo_root()
  },
)

terraform {
  source = "${path_relative_from_include("root")}/modules//${basename(get_terragrunt_dir())}///"

  after_hook "terraform_lock" {
    # removing auto-copied .terraform.lock.hcl file
    commands = ["init"]
    execute  = ["rm", "-f", "${get_terragrunt_dir()}/.terraform.lock.hcl"]
  }
}

remote_state {
  backend = "s3"

  config = {
    profile = local.account_name
    encrypt = true
    bucket  = local.tf_state_bucket
    key     = local.tf_state_key
    region  = local.tf_state_region
  }

  generate = {
    path      = "tg-backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "backend" {
  path      = "tg-backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket         = local.tf_state_bucket
    key            = local.tf_state_key
    region         = local.tf_state_region
    encrypt        = true
    use_lockfile   = true
  }
}
EOF
}

generate "providers" {
  path      = "tg-providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.36"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
}

provider "aws" {
  profile             = "${local.account_name}"
  region              = "${local.aws_region}"
  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = var.default_tags
  }
}
EOF
}

locals {
  layer      = basename(path_relative_to_include())                   # basement/network/etc.
  aws_region = basename(dirname(path_relative_to_include()))          # us-east-2/eu-central-1
  env        = basename(dirname(dirname(path_relative_to_include()))) # dev/stage/prod

  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  //account_id = local.account_vars.locals.account_id // get_aws_account_id() can't be used straight away because it lacks of AWS profile argument
  account_id = run_cmd("--terragrunt-quiet", "aws", "sts", "get-caller-identity", "--profile", local.account_name, "--query", "Account", "--output", "text")
  //account_name     = local.account_vars.locals.account_name
  account_name     = "pci-dss-${local.env}" // AWS profile must be configured with the same name in ~/.aws/config
  aws_region_short = local.aws_regions[local.aws_region]["name_short"]

  tf_state_bucket = "terraform-state-${local.account_id}"
  tf_state_key    = "terragrunt/${local.source_path}.tfstate"
  tf_state_region = "us-east-2"

  is_prod = try(local.account_vars.locals.is_prod, false)

  //route53_zone_name_public = local.account_vars.locals.basement_route53_zone_name_public
  route53_zone_name_public = "${local.account_name}.pomeshk.in"

  source_path = "envs/${local.env}/${local.aws_region}/${local.layer}"

  default_tags = {
    sourcePath = local.source_path
    env        = local.env
  }

  //
  // https://developer.hashicorp.com/terraform/language/functions/cidrsubnet
  // cidrsubnet(prefix, newbits, netnum)
  //
  network_vpc_cidr              = local.aws_regions[local.aws_region]["vpc_cidr"] # 10.x.0.0/16
  network_vpc_private_block_all = cidrsubnet(local.network_vpc_cidr, 1, 0)        # 10.x.0.0/17
  network_vpc_public_block_all  = cidrsubnet(local.network_vpc_cidr, 1, 1)        # 10.x.128.0/17

  network_vpc_private_block  = cidrsubnet(local.network_vpc_private_block_all, 1, 0) # 10.x.0-63.0/18
  network_vpc_database_block = cidrsubnet(local.network_vpc_private_block_all, 2, 2) # 10.x.64-95.0/19
  // network_vpc_firewall_block = cidrsubnet(local.network_vpc_private_block_all, 1, 1) # 10.x.96-127.0/19
  network_vpc_public_block = cidrsubnet(local.network_vpc_public_block_all, 3, 0) # 10.x.128.0/17 > 10.x.128.0/20

  network_vpc_public_subnets = [
    cidrsubnet(local.network_vpc_public_block, 4, 0), # /24
    cidrsubnet(local.network_vpc_public_block, 4, 1),
    cidrsubnet(local.network_vpc_public_block, 4, 2),
  ]
  network_vpc_private_subnets = [
    cidrsubnet(local.network_vpc_private_block, 3, 0), # /21
    cidrsubnet(local.network_vpc_private_block, 3, 1),
    cidrsubnet(local.network_vpc_private_block, 3, 2),
  ]
  network_vpc_database_subnets = [
    cidrsubnet(local.network_vpc_database_block, 3, 0), # /23
    cidrsubnet(local.network_vpc_database_block, 3, 1),
    cidrsubnet(local.network_vpc_database_block, 3, 2),
  ]
  // network_vpc_firewall_subnets = [
  //   cidrsubnet(local.network_vpc_firewall_block, 3, 0), # /23
  //   cidrsubnet(local.network_vpc_firewall_block, 3, 1),
  //   cidrsubnet(local.network_vpc_firewall_block, 3, 2),
  // ]

  aws_regions = {
    //
    // https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html#Concepts.RegionsAndAvailabilityZones.Regions
    //
    us-east-2 = {
      vpc_cidr   = "10.0.0.0/16"
      location   = "US East (Ohio)"
      name_short = "use2"
      azs        = ["a", "b", "c"]
    }
  }
}
