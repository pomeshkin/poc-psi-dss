locals {
  basement_create = {
    route53 = true
  }
  network_create = {
    vpc_nat_gw = false // temporary destroy to avoid extra costs
  }
}
