include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "module" {
  path = find_in_parent_folders("${path_relative_from_include("root")}/modules/${basename(get_terragrunt_dir())}.hcl")
}

inputs = {
  network_create = {
    elb                = true
    vpc_nat_gw         = true
    vpc_endpoints      = true
    vpc_flow_log       = false
    vpc_dedicated_acls = true
    route53_firewall   = true
  }
}
