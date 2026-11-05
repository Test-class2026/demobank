#!/bin/bash
# First-boot setup for the DemoBank server. Runs once, as root, through cloud-init.
# Watch it with: cloud-init status --wait  (log: /var/log/cloud-init-output.log)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y docker.io nginx python3-venv curl
systemctl enable --now docker
usermod -aG docker ubuntu

# Passwords are made here, on the server, so they never appear in Terraform state or in Git.
# Group ubuntu can read them: the app, the pipeline and you on Days 2 and 3.
install -d -m 0750 -o root -g ubuntu /etc/demobank
if [ ! -f /etc/demobank/oracle.env ]; then
  SYS_PASSWORD="Sys$(openssl rand -hex 12)"
  APP_PASSWORD="App$(openssl rand -hex 12)"
  cat > /etc/demobank/oracle.env <<EOF
ORACLE_PASSWORD=${SYS_PASSWORD}
APP_USER=demobank
APP_USER_PASSWORD=${APP_PASSWORD}
EOF
  cat > /etc/demobank/demobank.env <<EOF
DB_USER=demobank
DB_PASSWORD=${APP_PASSWORD}
DB_DSN=localhost:1521/FREEPDB1
EOF
  chown root:ubuntu /etc/demobank/*.env
  chmod 0640 /etc/demobank/*.env
fi

# Oracle Database Free 23ai. Published on 127.0.0.1 only: reachable from this server, never from outside.
# The data lives in a named volume, so it survives the container being replaced.
docker volume create oracle-data
docker run -d --name oracle --restart unless-stopped \
  -p 127.0.0.1:1521:1521 \
  --env-file /etc/demobank/oracle.env \
  -v oracle-data:/opt/oracle/oradata \
  gvenzl/oracle-free:23-slim

# Where the pipeline puts each release
install -d -o ubuntu -g ubuntu /opt/demobank /opt/demobank/releases

# nginx answers on port 80 and passes requests to the app on 127.0.0.1:8000.
# Until the pipeline deploys the app, that gives 502 Bad Gateway, which is expected.
cat > /etc/nginx/sites-available/demobank <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    location /static/ {
        alias /opt/demobank/current/app/static/;
        expires 1h;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/demobank /etc/nginx/sites-enabled/demobank
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
