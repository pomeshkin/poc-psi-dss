resource "aws_launch_template" "app" {
  count = local.create.asg_app ? 1 : 0

  name_prefix   = "${local.name_prefix}-asg-app-"
  image_id      = data.aws_ami.mysql.id
  instance_type = "t3.nano"

  # No SSH keypair — access via SSM Session Manager only
  key_name = null

  vpc_security_group_ids = [var.compute_sg.ec2_app]

  iam_instance_profile {
    arn = var.compute_iam.roles.ec2.instance_profile_arn
  }

  # Use spot instances for non-prod, on-demand for prod
  dynamic "instance_market_options" {
    for_each = local.env.is_prod ? [] : [1]
    content {
      market_type = "spot"
    }
  }

  user_data = base64encode(<<-USERDATA
#!/bin/bash
set -euo pipefail

# ── Start Nginx (service is disabled in the AMI intentionally) ────────────
systemctl start nginx
systemctl enable nginx

# ── Retrieve MySQL credentials from Secrets Manager ───────────────────────
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${aws_secretsmanager_secret.mysql[0].id}" \
  --region    "${local.region}" \
  --query     SecretString \
  --output    text)
MYSQL_USER=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
MYSQL_PASS=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

# ── Connectivity tests ────────────────────────────────────────────────────
# Test 1: https://secureweb.com — fail if not HTTP 200 or DNS unresolved
echo "Testing https://secureweb.com ..."
HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" --max-time 10 https://secureweb.com) || {
      echo "ERROR: Failed to resolve or connect to https://secureweb.com" >&2
      # systemctl stop nginx # Optional to fail ALB healthcheck
  exit 1
}
if [ "$${HTTP_CODE}" != "200" ]; then
  echo "ERROR: https://secureweb.com returned HTTP $${HTTP_CODE}, expected 200" >&2
  # systemctl stop nginx # Optional to fail ALB healthcheck
  exit 1
fi
echo "https://secureweb.com OK (HTTP $${HTTP_CODE})"

# Test 2: https://example.com — fail if not HTTP 200 or DNS unresolved
echo "Testing https://example.com ..."
HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" --max-time 10 https://example.com -k) || {
  echo "ERROR: Failed to resolve or connect to https://example.com" >&2
  # systemctl stop nginx # Optional to fail ALB healthcheck
  exit 1
}
if [ "$${HTTP_CODE}" != "200" ]; then
  echo "ERROR: https://example.com returned HTTP $${HTTP_CODE}, expected 200" >&2
  # systemctl stop nginx # Optional to fail ALB healthcheck
  exit 1
fi
echo "https://example.com OK (HTTP $${HTTP_CODE})"

# Test 3: MySQL connectivity on port 3306 using mysql client — fail if not reachable
MYSQL_HOST="${aws_instance.mysql[0].private_ip}"
echo "Testing MySQL connectivity at $${MYSQL_HOST}:3306 ..."

# Use option file to avoid passing password on the CLI (suppresses warning)
APP_CNF="$(mktemp)"
chmod 600 "$${APP_CNF}"
cat > "$${APP_CNF}" <<EOF
[client]
user=$${MYSQL_USER}
password=$${MYSQL_PASS}
host=$${MYSQL_HOST}
port=3306
EOF

mysql \
  --defaults-file="$${APP_CNF}" \
  --ssl-mode=REQUIRED \
  --tls-version=TLSv1.3 \
  --connect-timeout=10 \
  --execute="SELECT 1;" > /dev/null 2>&1 || {
  rm -f "$${APP_CNF}"
  echo "ERROR: Cannot connect to MySQL at $${MYSQL_HOST}:3306 as $${MYSQL_USER}" >&2
  # systemctl stop nginx # Optional to fail ALB healthcheck
  exit 1
}
rm -f "$${APP_CNF}"
echo "MySQL connectivity at $${MYSQL_HOST}:3306 OK"
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.default_tags, {
      Name = "${local.name_prefix}-asg-app-${local.region_short}"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  count = local.create.asg_app ? 1 : 0

  name_prefix         = "${local.name_prefix}-asg-app-"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.compute_vpc.private_subnets

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app[0].id
    version = "$Latest"
  }

  target_group_arns = [var.compute_alb.target_groups["ex-app"].arn]

  default_instance_warmup = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg-app-${local.region_short}"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.default_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
