variable "env" {
  type = any
}

variable "network_create" {
  type    = map(string)
  default = {}
}

variable "network_vpc_cidr" {
  type = string
}

variable "network_vpc_azs" {
  type = list(string)
}

variable "network_vpc_public_subnets" {
  type = list(string)
}

variable "network_vpc_private_subnets" {
  type = list(string)
}

variable "network_vpc_database_subnets" {
  type = list(string)
}

variable "network_route53" {
  type = any
}

variable "network_s3" {
  type = any
}

variable "network_allowed_cidrs_ingress" {
  type = list(string)
}

variable "network_allowed_cidrs_egress" {
  type    = list(string)
  default = []
}

variable "default_tags" {
  type    = map(string)
  default = {}
}
