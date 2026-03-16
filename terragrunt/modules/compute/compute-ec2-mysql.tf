data "aws_ami" "mysql" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["pci-dss-nginx-mysql-2026-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "random_password" "mysql" {
  count = local.create.ec2_mysql ? 1 : 0

  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "mysql" {
  count = local.create.ec2_mysql ? 1 : 0

  name                    = "${local.name_prefix}/ec2/mysql"
  recovery_window_in_days = 0

  tags = var.default_tags
}

resource "aws_secretsmanager_secret_version" "mysql" {
  count = local.create.ec2_mysql ? 1 : 0

  secret_id = aws_secretsmanager_secret.mysql[0].id
  secret_string = jsonencode({
    username = "appuser"
    password = random_password.mysql[0].result
  })
}

resource "aws_instance" "mysql" {
  count = local.create.ec2_mysql ? 1 : 0

  ami                    = data.aws_ami.mysql.id
  instance_type          = "t3.nano"
  subnet_id              = var.compute_vpc.database_subnets[0]
  vpc_security_group_ids = [var.compute_sg.ec2_mysql]
  iam_instance_profile   = var.compute_iam.roles.ec2.instance_profile_name

  # No SSH keypair - access via SSM Session Manager only
  key_name = null

  user_data = <<-USERDATA
#!/bin/bash
set -euo pipefail

# ── 0. Create 1 GB swap file ──────────────────────────────────────────────
# For POC only, to use small instance types without OOM issues
# if [ ! -f /swapfile ]; then
#   fallocate -l 1G /swapfile
#   chmod 600 /swapfile
#   mkswap /swapfile
#   swapon /swapfile
#   echo '/swapfile none swap sw 0 0' >> /etc/fstab
# fi

# ── 1. Start MySQL ────────────────────────────────────────────────────────
systemctl start mysqld
systemctl enable mysqld
# Wait until the socket is ready (max 60 s)
PING_CNF="$(mktemp)"
chmod 600 "$${PING_CNF}"
printf '[client]\nuser=root\npassword=\n' > "$${PING_CNF}"
for i in $(seq 1 60); do
  mysqladmin --defaults-file="$${PING_CNF}" ping --silent 2>/dev/null && break
  sleep 1
done
rm -f "$${PING_CNF}"

# ── 2. Retrieve credentials from Secrets Manager ──────────────────────────
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${aws_secretsmanager_secret.mysql[0].id}" \
  --region    "${local.region}" \
  --query     SecretString \
  --output    text)
APP_USER=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
APP_PASS=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

# ── 3. Reset root password ────────────────────────────────────────────────
NEW_ROOT_PASSWORD="$${APP_PASS}"
# Use option file to avoid passing password on the CLI (suppresses warning)
ROOT_CNF="$(mktemp)"
chmod 600 "$${ROOT_CNF}"
cat > "$${ROOT_CNF}" <<EOF
[client]
user=root
password=
EOF

mysql --defaults-file="$${ROOT_CNF}" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '$${NEW_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL

# Update option file with new root password for subsequent commands
cat > "$${ROOT_CNF}" <<EOF
[client]
user=root
password=$${NEW_ROOT_PASSWORD}
EOF

# ── 4. Create application database and user ───────────────────────────────
APP_DB="appdb"
# Grant remote access from any host ('%') so the app server (different IP)
# can connect. The security group restricts port 3306 to the VPC CIDR only.
# Drop the localhost-scoped user if it exists from a previous run so that
# 'CREATE USER IF NOT EXISTS' does not silently skip the @'%' creation.
mysql --defaults-file="$${ROOT_CNF}" <<SQL
DROP USER IF EXISTS '$${APP_USER}'@'localhost';
CREATE DATABASE IF NOT EXISTS \`$${APP_DB}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$${APP_USER}'@'%'
  IDENTIFIED BY '$${APP_PASS}'
  REQUIRE SSL;
GRANT ALL PRIVILEGES ON \`$${APP_DB}\`.* TO '$${APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

# Remove the temporary credentials file
rm -f "$${ROOT_CNF}"
echo "MySQL setup complete."
USERDATA

  user_data_replace_on_change = true

  tags = merge(var.default_tags, {
    Name = "${local.name_prefix}-ec2-mysql-${local.region_short}"
  })
}
