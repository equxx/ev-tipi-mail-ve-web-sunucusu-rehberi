#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die 'Bu betik root olarak çalıştırılmalı (sudo).'
[[ $# -eq 1 ]] || { printf 'Kullanım: sudo %s /path/to/server.env\n' "$0"; exit 2; }
env_file="$1"
[[ -f "$env_file" ]] || die "Config bulunamadı: $env_file"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${WEB_HOSTNAME:?WEB_HOSTNAME eksik}"
[[ "$WEB_HOSTNAME" != 'example.com' ]] || die 'Önce gerçek WEB_HOSTNAME yazın.'
[[ "$WEB_HOSTNAME" =~ ^[A-Za-z0-9.-]+$ ]] || die "Geçersiz DNS adı: $WEB_HOSTNAME"
command -v nginx >/dev/null 2>&1 || die 'nginx bulunamadı. Önce install-linux.sh çalıştırın.'
command -v systemctl >/dev/null 2>&1 || die 'systemctl bulunamadı.'

php_unit="$(systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' | awk '$1 ~ /^php.*-fpm\.service$/ { print $1; exit }')"
[[ -n "$php_unit" ]] || die 'php-fpm systemd servisi bulunamadı.'
systemctl enable --now "$php_unit"

php_socket="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' -print -quit 2>/dev/null || true)"
[[ -n "$php_socket" ]] || die 'Çalışan bir PHP-FPM socket’i bulunamadı.'

site_root="/var/www/$WEB_HOSTNAME"
public_root="$site_root/public"
site_file="/etc/nginx/sites-available/$WEB_HOSTNAME.conf"
install -d -m 0755 "$public_root"

if [[ ! -e "$public_root/index.html" && ! -e "$public_root/index.php" ]]; then
    cat > "$public_root/index.html" <<EOF
<!doctype html>
<html lang="tr"><meta charset="utf-8"><title>$WEB_HOSTNAME</title>
<h1>$WEB_HOSTNAME hazır</h1>
<p>Nginx ve PHP-FPM tabanı çalışıyor.</p>
EOF
fi

cat > "$site_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $WEB_HOSTNAME;

    root $public_root;
    index index.html index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
EOF

chown -R www-data:www-data "$site_root"
chmod 0755 "$site_root" "$public_root"
ln -sfn "$site_file" "/etc/nginx/sites-enabled/$WEB_HOSTNAME.conf"

nginx -t
systemctl enable --now nginx
systemctl reload nginx

printf '\nWeb tabanı hazır: http://%s/\n' "$WEB_HOSTNAME"
printf '%s\n' 'TLS için DNS ve dış TCP 80 hazır olduğunda: certbot --nginx -d <alan-adı> -d mail.<alan-adı>'
