#!/usr/bin/env bash
# =============================================================================
# Packer provisioner script
# Installs: Nginx (TLSv1.3, self-signed cert, disabled service)
#           MySQL 9.x Community (TLSv1.3, disabled service)
# OS: Amazon Linux 2023 (x86_64)
# =============================================================================
set -euo pipefail

CERT_DIR="/etc/nginx/ssl"
CERT_KEY="${CERT_DIR}/server.key"
CERT_CRT="${CERT_DIR}/server.crt"
NGINX_CONF="/etc/nginx/conf.d/default.conf"
MYSQL_CONF="/etc/my.cnf.d/tls.cnf"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ─────────────────────────────────────────────
# 1. System update
# ─────────────────────────────────────────────
log "Updating system packages..."
dnf update -y --quiet

# ─────────────────────────────────────────────
# 2. Install Nginx
# ─────────────────────────────────────────────
log "Installing Nginx..."
dnf install -y nginx openssl

# ── Generate self-signed TLSv1.3 certificate ──
log "Generating self-signed TLSv1.3 certificate..."
mkdir -p "${CERT_DIR}"
openssl req -x509 -nodes -newkey ec \
  -pkeyopt ec_paramgen_curve:P-384 \
  -keyout "${CERT_KEY}" \
  -out    "${CERT_CRT}" \
  -days 3650 \
  -subj "/C=US/ST=Ohio/L=Columbus/O=PCI-DSS-Dev/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 600 "${CERT_KEY}"
chmod 644 "${CERT_CRT}"

# ── Write Nginx virtual-host config ───────────
log "Writing Nginx configuration..."
cat > "${NGINX_CONF}" <<'NGINX_EOF'
# Redirect HTTP → HTTPS
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    return 301  https://$host$request_uri;
}

# HTTPS server with TLSv1.3 only
server {
    listen              443 ssl default_server;
    listen              [::]:443 ssl default_server;
    server_name         _;
    http2               on;

    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # TLSv1.3 only
    ssl_protocols       TLSv1.3;
    ssl_prefer_server_ciphers off;

    ssl_session_timeout  1d;
    ssl_session_cache    shared:SSL:10m;
    ssl_session_tickets  off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    root  /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /healthz {
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
NGINX_EOF

# ── Dummy start page ──────────────────────────
log "Writing Nginx dummy start page..."
cat > /usr/share/nginx/html/index.html <<'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>PCI-DSS — Nginx OK</title>
  <style>
    body { font-family: sans-serif; display:flex; justify-content:center;
           align-items:center; height:100vh; margin:0; background:#f4f6f8; }
    .box { text-align:center; padding:2rem 3rem; background:#fff;
           border-radius:8px; box-shadow:0 2px 12px rgba(0,0,0,.1); }
    h1 { color:#2c7be5; }
  </style>
</head>
<body>
  <div class="box">
    <h1>&#9989; Nginx is running</h1>
    <p>PCI-DSS demo instance &mdash; HTTPS / TLSv1.3</p>
  </div>
</body>
</html>
HTML_EOF

# ── Validate config and disable service ───────
log "Validating Nginx config..."
nginx -t

log "Disabling Nginx service (will be started via user-data)..."
systemctl disable nginx
systemctl stop nginx || true

# ─────────────────────────────────────────────
# 3. Install MySQL 9.x Community
# ─────────────────────────────────────────────
log "Adding MySQL Community repository..."

# Import MySQL GPG key
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023

# Install the MySQL Community repo RPM for EL9 (Amazon Linux 2023 is EL9-based)
dnf install -y https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm

# Disable 8.4 channel, enable 9.x Innovation channel
log "Switching to MySQL 9.x channel..."
dnf config-manager --disable mysql84-community        || true
dnf config-manager --disable mysql84-community-debuginfo || true
dnf config-manager --disable mysql84-community-source    || true

dnf config-manager --enable  mysql-innovation-community         || true

log "Installing MySQL Community Server 9.x..."
dnf install -y mysql-community-server

# ── TLSv1.3 configuration ─────────────────────
log "Configuring MySQL for TLSv1.3..."
cat > "${MYSQL_CONF}" <<'MYSQL_EOF'
[mysqld]
# Force TLSv1.3 only
tls_version         = TLSv1.3

# Use the bundled OpenSSL auto-generated certs (created on first start)
# To use custom certs, override ssl_ca / ssl_cert / ssl_key here.

# Require SSL for all remote connections
require_secure_transport = ON

# General hardening
local_infile        = 0
symbolic_links      = 0
MYSQL_EOF

# ── First-boot initialisation (to pre-populate data dir) ──
log "Initialising MySQL data directory..."
mysqld --initialize-insecure --user=mysql 2>&1 | tail -20

# ── Disable service (will be started via user-data) ───────
log "Disabling MySQL service (will be started via user-data)..."
systemctl disable mysqld
systemctl stop mysqld || true

# ─────────────────────────────────────────────
# 4. Clean up
# ─────────────────────────────────────────────
log "Cleaning up..."
dnf clean all
rm -rf /var/cache/dnf /tmp/install.sh

log "=== Provisioning complete ==="
