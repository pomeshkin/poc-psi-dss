dependency "basement" {
  config_path = "../basement"

  skip_outputs                            = tobool(get_env("TG_SKIP_OUTPUTS", "false"))
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
  mock_outputs = {
    route53 = {}
    iam     = {}
    s3      = {}
  }
}

inputs = {
  network_route53 = try(dependency.basement.outputs.route53, {})
  network_s3      = try(dependency.basement.outputs.s3, {})
}
