output "sg" {
  value = {
    alb_ext       = try(aws_security_group.alb_ext[0].id, "")
    ec2_app       = try(aws_security_group.ec2_app[0].id, "")
    ec2_mysql     = try(aws_security_group.ec2_mysql[0].id, "")
    vpc_endpoints = try(aws_security_group.vpc_endpoints[0].id, "")
    packer        = try(aws_security_group.packer[0].id, "")
  }
}
