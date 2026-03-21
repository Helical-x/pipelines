#!/bin/bash

# ─────────────────────────────────────────────
#  Nginx Config Generator
# ─────────────────────────────────────────────

set -e

BOLD="\033[1m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║     Nginx Config Generator           ║"
echo "╚══════════════════════════════════════╝"
echo -e "${RESET}"

DOMAIN=$1
PORT=$2
INCLUDE_WWW=$3
ENABLE_SSL=$4
EMAIL=$5

# ── Build server_name ─────────────────────────

if [[ "${INCLUDE_WWW^^}" == "Y" ]]; then
  SERVER_NAME="$DOMAIN www.$DOMAIN"
else
  SERVER_NAME="$DOMAIN"
fi

# ── Generate config ───────────────────────────

echo -e "\n${YELLOW}⚙ Generating $OUTPUT...${RESET}\n"

if [[ "${ENABLE_SSL^^}" == "Y" ]]; then

  cat >"$OUTPUT" <<NGINX
server {
    listen 80;
    server_name $SERVER_NAME;

    # Certbot ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $SERVER_NAME;

    # SSL — managed by Certbot (Let's Encrypt)
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header X-Frame-Options        "SAMEORIGIN"    always;
    add_header X-Content-Type-Options "nosniff"       always;
    add_header X-XSS-Protection       "1; mode=block" always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # Proxy to backend on port $PORT
    location / {
        proxy_pass         http://127.0.0.1:$PORT;
        proxy_http_version 1.1;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection        "";

        proxy_read_timeout    60s;
        proxy_send_timeout    60s;
        proxy_connect_timeout 10s;
    }

    # Block hidden files
    location ~ /\. {
        deny all;
    }
}
NGINX

else

  cat >"$OUTPUT" <<NGINX
server {
    listen 80;
    server_name $SERVER_NAME;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # Proxy to backend on port $PORT
    location / {
        proxy_pass         http://127.0.0.1:$PORT;
        proxy_http_version 1.1;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection        "";

        proxy_read_timeout    60s;
        proxy_send_timeout    60s;
        proxy_connect_timeout 10s;
    }

    # Block hidden files
    location ~ /\. {
        deny all;
    }
}
NGINX

fi

# ── Enable Nginx site ─────────────────────────────────────
echo "🔗 Enabling Nginx site..."
sudo cp /tmp/"$DOMAIN".conf /etc/nginx/sites-available/$DOMAIN
sudo ln -sf /etc/nginx/sites-available/"$DOMAIN" \
  /etc/nginx/sites-enabled/"$DOMAIN"

sudo nginx -t
sudo systemctl reload nginx

# ── Run Certbot ───────────────────────────────────────────
DOMAINS="-d $DOMAIN"
if [ "$INCLUDE_WWW" = "true" ]; then
  DOMAINS="$DOMAINS -d www.$DOMAIN"
fi

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "🔐 Issuing new certificate for $DOMAIN..."
  sudo certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    "$DOMAINS"
else
  echo "🔄 Renewing existing certificate for $DOMAIN..."
  sudo certbot renew --nginx --non-interactive \
    --cert-name "$DOMAIN"
fi

echo "🔁 Reloading Nginx with SSL..."
sudo nginx -t
sudo systemctl reload nginx

echo "✅ Done — $DOMAIN is live with SSL"
