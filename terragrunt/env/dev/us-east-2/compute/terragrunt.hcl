include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "module" {
  path = find_in_parent_folders("${path_relative_from_include("root")}/modules/${basename(get_terragrunt_dir())}.hcl")
}

inputs = {}
