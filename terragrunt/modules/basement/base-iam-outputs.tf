output "iam" {
  value = {
    roles = {
      ec2 = {
        name                  = concat(aws_iam_role.ec2.*.name, [""])[0]
        arn                   = concat(aws_iam_role.ec2.*.arn, [""])[0]
        instance_profile_name = concat(aws_iam_instance_profile.ec2.*.name, [""])[0]
        instance_profile_arn  = concat(aws_iam_instance_profile.ec2.*.arn, [""])[0]
      }
    }
  }
}
