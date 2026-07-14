#!/bin/bash
# EC2 bootstrap script — Docker-based deployment
# Runs once on first launch via EC2 User Data
set -e

# System updates
yum update -y
yum install -y git

# Install Docker
yum install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Install Docker Compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Install nginx for SSL termination + WebSocket proxy
yum install -y nginx
systemctl enable nginx

# App directory
mkdir -p /app
chown ec2-user:ec2-user /app

# Clone repo
sudo -u ec2-user git clone https://github.com/Pranjali86/sync-canvas.git /app/sync-canvas

# Write .env — update these values before first deploy!
cat > /app/sync-canvas/.env <<'EOF'
DB_PASSWORD=CHANGE_ME_STRONG_PASSWORD
JWT_SECRET=CHANGE_ME_LONG_RANDOM_SECRET
CORS_ORIGINS=https://CHANGE_ME.cloudfront.net
EOF
chown ec2-user:ec2-user /app/sync-canvas/.env
chmod 600 /app/sync-canvas/.env

# Start the stack
cd /app/sync-canvas
sudo -u ec2-user docker compose up -d --build

# nginx reverse proxy + WebSocket config
cat > /etc/nginx/conf.d/excalidraw.conf <<'NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_set_header   X-Real-IP  $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf
nginx -t && systemctl start nginx

echo "Bootstrap complete — stack is starting up"
