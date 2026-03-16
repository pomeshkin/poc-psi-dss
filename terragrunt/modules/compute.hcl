dependency "basement" {
  config_path = "../basement"

  skip_outputs                            = tobool(get_env("TG_SKIP_OUTPUTS", "false"))
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
  mock_outputs = {
    iam = {}
  }
}

dependency "network" {
  config_path = "../network"

  skip_outputs                            = tobool(get_env("TG_SKIP_OUTPUTS", "false"))
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
  mock_outputs = {
    vpc     = {}
    sg      = {}
    alb_ext = {}
  }
}

inputs = {
  compute_iam = try(dependency.basement.outputs.iam, {})
  compute_vpc = try(dependency.network.outputs.vpc, {})
  compute_sg  = try(dependency.network.outputs.sg, {})
  compute_alb = try(dependency.network.outputs.alb_ext, {})
}
