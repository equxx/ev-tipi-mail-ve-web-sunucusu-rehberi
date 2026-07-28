#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    printf 'Kullanım: sudo %s /path/to/server.env\n' "$0"
}

die() {
    printf 'HATA: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'UYARI: %s\n' "$*" >&2
}

[[ "${EUID}" -eq 0 ]] || die 'Bu betik root olarak çalıştırılmalı (sudo).'
[[ $# -eq 1 ]] || { usage; exit 2; }
env_file="$1"
[[ -f "$env_file" ]] || die "Config bulunamadı: $env_file"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${MAIL_DOMAIN:?MAIL_DOMAIN eksik}"
: "${MAIL_HOSTNAME:?MAIL_HOSTNAME eksik}"
: "${WEB_HOSTNAME:?WEB_HOSTNAME eksik}"
: "${SERVER_LAN_IP:?SERVER_LAN_IP eksik}"

[[ "$MAIL_DOMAIN" != 'example.com' ]] || die 'Önce server.env içindeki örnek alan adını değiştirin.'
[[ "$MAIL_HOSTNAME" != 'mail.example.com' ]] || die 'Önce server.env içindeki örnek mail adını değiştirin.'
[[ "$WEB_HOSTNAME" != 'example.com' ]] || die 'Önce server.env içindeki örnek web adını değiştirin.'
for dns_name in "$MAIL_DOMAIN" "$MAIL_HOSTNAME" "$WEB_HOSTNAME"; do
    [[ "$dns_name" =~ ^[A-Za-z0-9.-]+$ ]] || die "Geçersiz DNS adı: $dns_name"
done

command -v apt-get >/dev/null 2>&1 || die 'Bu betik apt tabanlı Ubuntu/Debian içindir.'
command -v systemctl >/dev/null 2>&1 || die 'systemd bulunamadı.'

. /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Desteklenmeyen dağıtım: ${ID:-bilinmiyor}. Ubuntu veya Debian kullanın." ;;
esac

codename="${VERSION_CODENAME:-}"
if [[ -z "$codename" ]]; then
    command -v lsb_release >/dev/null 2>&1 || apt-get update
    command -v lsb_release >/dev/null 2>&1 || apt-get install -y lsb-release
    codename="$(lsb_release -cs)"
fi

printf 'Dağıtım: %s (%s)\n' "$PRETTY_NAME" "$codename"
printf 'Mail: %s | Web: %s | LAN: %s\n' "$MAIL_HOSTNAME" "$WEB_HOSTNAME" "$SERVER_LAN_IP"

export DEBIAN_FRONTEND=readline
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release unzip \
    nginx php-fpm php-cli php-mysql php-intl php-xml php-mbstring php-curl php-zip php-gd \
    mariadb-server \
    postfix dovecot-imapd dovecot-lmtpd dovecot-sieve \
    redis-server certbot python3-certbot-nginx \
    ufw dnsutils

# Rspamd’ın Ubuntu/Debian için önerdiği imzalı resmi deposu.
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://rspamd.com/apt-stable/gpg.key |
    gpg --dearmor --yes -o /usr/share/keyrings/rspamd.gpg
printf 'deb [signed-by=/usr/share/keyrings/rspamd.gpg] https://rspamd.com/apt-stable %s main\n' "$codename" \
    > /etc/apt/sources.list.d/rspamd.list
apt-get update
apt-get install -y --no-install-recommends rspamd

for service_name in nginx mariadb postfix dovecot redis-server rspamd; do
    if ! systemctl enable --now "$service_name"; then
        warn "$service_name başlatılamadı; yapılandırma adımından sonra tekrar kontrol edin."
    fi
done

printf '\nKurulum bitti.\n'
printf '%s\n' 'Bu betik router portlarını, DNS kayıtlarını, TLS sertifikasını veya UFW kurallarını değiştirmedi.'
printf '%s\n' 'Sıradaki adımlar:'
printf '  sudo ./scripts/configure-mail-baseline.sh %s\n' "$env_file"
printf '  sudo ./scripts/configure-web-site.sh %s\n' "$env_file"
printf '  sudo ./scripts/audit-linux.sh %s\n' "$env_file"
