# Packer — pci-dss-nginx-mysql AMI

This directory contains a Packer HCL template that bakes an Amazon Linux 2023 AMI with:

| Component | Details |
|-----------|---------|
| **Nginx** | Latest from AL2023 repo, HTTPS-only (TLSv1.3), self-signed EC P-384 certificate, service **disabled** |
| **MySQL** | Community 9.x Innovation, TLSv1.3 only (`require_secure_transport=ON`), service **disabled** |
| **Connection** | AWS Systems Manager (SSM) — no SSH port required |

---

## Prerequisites

```bash
# 1. Packer ≥ 1.9
packer version

# 2. AWS CLI profile configured
aws configure --profile pci-dss-dev

# 3. Install Packer Amazon plugin
packer init git/poc-psi-dss/packer/nginx-mysql.pkr.hcl
```

---

## Build the AMI

```bash
cd git/poc-psi-dss/packer

packer build nginx-mysql.pkr.hcl
```

Resulting AMI name: `pci-dss-nginx-mysql-YYYY-MM-DD-hh-mm`

---

## Installing and Starting the AWS SSM Agent via EC2 User Data

Amazon Linux 2023 ships with the SSM Agent pre-installed but it may not be running.
The snippet below installs (or upgrades) the agent and ensures it is active before
starting the application services:

```bash
#!/bin/bash
set -euo pipefail

# ── Install / upgrade AWS SSM Agent ──────────────────────────────────────────
# Amazon Linux 2023 hosts the agent in its own dnf repo (already enabled).
# This is a no-op if the latest version is already present.
dnf install -y amazon-ssm-agent

# ── Enable and start SSM Agent ────────────────────────────────────────────────
systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

# Confirm the agent is running
systemctl is-active --quiet amazon-ssm-agent && \
  echo "SSM Agent is running." || \
  echo "WARNING: SSM Agent failed to start."
```

> **Note:** The EC2 instance must be associated with an IAM instance profile that includes
> the `AmazonSSMManagedInstanceCore` policy (profile `dev-ec2-default-use2` already covers this).

---

## Starting Nginx via EC2 User Data

Paste the following snippet into the **User Data** field when launching an EC2 instance from the baked AMI:

```bash
#!/bin/bash
# Start Nginx (service is disabled in the AMI intentionally)
systemctl start nginx
systemctl enable nginx   # optional: persist across reboots
```

---

## Starting MySQL via EC2 User Data

```bash
#!/bin/bash
# Start MySQL (service is disabled in the AMI intentionally)
systemctl start mysqld
systemctl enable mysqld  # optional: persist across reboots
```

---

## MySQL — First-Boot Setup via User Data

The AMI ships with an **empty root password** (initialised with `--initialize-insecure`).
Use the block below to set a root password and create an application database in a single user-data script:

```bash
#!/bin/bash
set -euo pipefail

# ── 1. Start MySQL ────────────────────────────────────────────────────────────
systemctl start mysqld
systemctl enable mysqld

# Wait until the socket is ready (max 60 s)
for i in $(seq 1 60); do
  mysqladmin --user=root --password='' ping --silent 2>/dev/null && break
  sleep 1
done

# ── 2. Reset root password ────────────────────────────────────────────────────
NEW_ROOT_PASSWORD="S3cur3R00tP@ss!"          # <── change this

mysql --user=root --password='' <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL

# ── 3. Create application database and user ───────────────────────────────────
APP_DB="appdb"
APP_USER="appuser"
APP_PASS="AppUs3rP@ss!"                      # <── change this

mysql --user=root --password="${NEW_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${APP_DB}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${APP_USER}'@'localhost'
  IDENTIFIED BY '${APP_PASS}'
  REQUIRE SSL;

GRANT ALL PRIVILEGES ON \`${APP_DB}\`.* TO '${APP_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "MySQL setup complete."
```

---

## MySQL — Connection Test

Run the following from inside the EC2 instance (or via SSM Session Manager) to verify TLSv1.3 is enforced:

```bash
# Connect and inspect TLS cipher / protocol
mysql \
  --user=appuser \
  --password='AppUs3rP@ss!' \
  --host=127.0.0.1 \
  --port=3306 \
  --ssl-mode=REQUIRED \
  appdb \
  --execute="
    SELECT
      VARIABLE_VALUE AS tls_version
    FROM performance_schema.session_status
    WHERE VARIABLE_NAME = 'Ssl_version';

    SELECT
      VARIABLE_VALUE AS tls_cipher
    FROM performance_schema.session_status
    WHERE VARIABLE_NAME = 'Ssl_cipher';

    SHOW DATABASES;
  "
```

Expected output excerpt:

```
+-------------+
| tls_version |
+-------------+
| TLSv1.3     |
+-------------+
```

---

## Nginx — HTTPS Smoke Test (from the instance)

```bash
# Self-signed cert → use -k / --insecure
curl -sk https://127.0.0.1/ | grep -o 'Nginx is running'

# Verbose TLS handshake inspection
curl -sv --tlsv1.3 https://127.0.0.1/healthz 2>&1 | grep -E 'SSL|TLS|subject'
```
