data "aws_partition" "current" {}

/*data "aws_iam_roles" "sso_admin" {
  name_regex  = var.sso_admin_role_name_regex
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}*/