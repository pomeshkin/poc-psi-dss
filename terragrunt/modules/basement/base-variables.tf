variable "env" {
  type = any
}

variable "basement_create" {
  type    = map(string)
  default = {}
}

variable "basement_route53_zone_name_public" {
  type    = string
  default = ""
}

variable "default_tags" {
  type    = map(string)
  default = {}
}
