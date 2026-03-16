variable "compute_create" {
  type    = map(string)
  default = {}
}

variable "compute_vpc" {
  type = any
}

variable "compute_sg" {
  type    = map(string)
  default = {}
}

variable "compute_iam" {
  type = any
}

variable "compute_alb" {
  type = any
}

variable "default_tags" {
  type    = map(string)
  default = {}
}

variable "env" {
  type = any
}
