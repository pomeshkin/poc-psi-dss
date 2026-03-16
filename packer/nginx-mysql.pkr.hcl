packer {
  required_version = ">= 1.9.0"

  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ──────────────────────────────────────────────
# Data sources
# ──────────────────────────────────────────────

data "amazon-ami" "amzn2023" {
  profile = "pci-dss-dev"
  region  = "us-east-2"

  filters = {
    name                = "al2023-ami-2023.10.2026*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
    architecture        = "x86_64"
  }

  owners      = ["amazon"]
  most_recent = true
}

# ──────────────────────────────────────────────
# Local variables
# ──────────────────────────────────────────────

locals {
  timestamp = formatdate("YYYY-MM-DD-hh-mm", timestamp())
  ami_name  = "pci-dss-nginx-mysql-${local.timestamp}"

  # Injected as EC2 user-data so SSM Agent is running
  # before Packer opens its SSH-over-SSM tunnel.
  ssm_userdata = <<-USERDATA
    #!/bin/bash
    set -euo pipefail
    # Install / upgrade SSM Agent (idempotent on AL2023)
    dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start  amazon-ssm-agent
    # Block until the agent is active (max 120 s)
    for i in $(seq 1 120); do
      systemctl is-active --quiet amazon-ssm-agent && break
      sleep 1
    done
  USERDATA
}

# ──────────────────────────────────────────────
# Source block
# ──────────────────────────────────────────────

source "amazon-ebs" "pci_dss" {
  profile       = "pci-dss-dev"
  region        = "us-east-2"
  ami_name      = local.ami_name
  source_ami    = data.amazon-ami.amzn2023.id
  instance_type = "t3.small"

  # ── User data: install & start SSM Agent before Packer connects ──
  user_data = local.ssm_userdata

  # ── IAM Instance Profile ───────────────────
  iam_instance_profile = "dev-ec2-default-use2"

  # ── Network: lookup by tags ────────────────
  vpc_filter {
    filters = {
      "tag:Name" = "dev"
    }
  }

  subnet_filter {
    filters = {
      "tag:Name" = "dev-public-us-east-2a"
    }
    most_free = true
  }

  security_group_filter {
    filters = {
      "tag:Name" = "dev-packer"
    }
  }

  # ── SSM connection (no SSH port required) ─
  communicator                = "ssh"
  ssh_interface               = "session_manager"
  ssh_username                = "ec2-user"
  associate_public_ip_address = true

  # ── EBS root volume ───────────────────────
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # ── AMI tags ─────────────────────────────
  tags = {
    Name        = local.ami_name
    Project     = "pci-dss"
    Environment = "dev"
    BuildDate   = local.timestamp
    OS          = "AmazonLinux2023"
    Stack       = "nginx-mysql"
  }

  # ── Snapshot tags ─────────────────────────
  snapshot_tags = {
    Name    = local.ami_name
    Project = "pci-dss"
  }
}

# ──────────────────────────────────────────────
# Build block
# ──────────────────────────────────────────────

build {
  name    = "pci-dss-nginx-mysql"
  sources = ["source.amazon-ebs.pci_dss"]

  # ── 1. Upload provisioner script ──────────
  provisioner "file" {
    source      = "scripts/install.sh"
    destination = "/tmp/install.sh"
  }

  # ── 2. Run installation ───────────────────
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install.sh",
      "sudo /tmp/install.sh"
    ]
  }
}
