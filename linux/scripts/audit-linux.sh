#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 1 ]] || { printf 'Kullanım: %s /path/to/server.env\n' "$0"; exit 2; }
env_file="$1"
[[ -f "$env_file" ]] || die "Config bulunamadı: $env_file"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${MAIL_DOMAIN:?MAIL_DOMAIN eksik}"
: "${MAIL_HOSTNAME:?MAIL_HOSTNAME eksik}"
: "${WEB_HOSTNAME:?WEB_HOSTNAME eksik}"
for dns_name in "$MAIL_DOMAIN" "$MAIL_HOSTNAME" "$WEB_HOSTNAME"; do
    [[ "$dns_name" =~ ^[A-Za-z0-9.-]+$ ]] || die "Geçersiz DNS adı: $dns_name"
done

printf 'Linux ev sunucusu salt-okunur denetimi\n'
printf 'Mail: %s | Web: %s\n\n' "$MAIL_HOSTNAME" "$WEB_HOSTNAME"

printf '%-14s %s\n' 'Servis' 'Durum'
printf '%-14s %s\n' '------' '-----'
for service_name in nginx mariadb postfix dovecot redis-server rspamd; do
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$service_name"; then
        printf '%-14s %s\n' "$service_name" 'active'
    else
        printf '%-14s %s\n' "$service_name" 'NOT active'
    fi
done

printf '\nSeçilen dinleme portları:\n'
if command -v ss >/dev/null 2>&1; then
    ss -lntup 2>/dev/null | awk 'NR == 1 || $5 ~ /:(25|80|443|465|587|993)$/'
else
    printf '%s\n' 'ss bulunamadı.'
fi

printf '\nYapılandırma testleri:\n'
if command -v nginx >/dev/null 2>&1; then nginx -t 2>&1 || true; else printf '%s\n' 'nginx bulunamadı'; fi
if command -v postfix >/dev/null 2>&1; then postfix check 2>&1 || true; else printf '%s\n' 'postfix bulunamadı'; fi
if command -v doveconf >/dev/null 2>&1; then doveconf -n >/dev/null 2>&1 && printf '%s\n' 'dovecot: OK' || printf '%s\n' 'dovecot: yapılandırma hatası'; else printf '%s\n' 'doveconf bulunamadı'; fi
if command -v rspamadm >/dev/null 2>&1; then rspamadm configtest 2>&1 || true; else printf '%s\n' 'rspamadm bulunamadı'; fi

printf '\nUFW durumu (değişiklik yapılmaz):\n'
if command -v ufw >/dev/null 2>&1; then ufw status verbose || true; else printf '%s\n' 'ufw kurulu değil'; fi

printf '\nGenel DNS görünümü (1.1.1.1):\n'
if command -v dig >/dev/null 2>&1; then
    printf 'A %s: ' "$WEB_HOSTNAME"; dig +short A "$WEB_HOSTNAME" @1.1.1.1
    printf 'MX %s: ' "$MAIL_DOMAIN"; dig +short MX "$MAIL_DOMAIN" @1.1.1.1
    printf 'A %s: ' "$MAIL_HOSTNAME"; dig +short A "$MAIL_HOSTNAME" @1.1.1.1
else
    printf '%s\n' 'dig bulunamadı; dnsutils kurun.'
fi

printf '\nManuel kontroller:\n'
printf '%s\n' '- Mobil internetten HTTPS, IMAPS 993 ve submission 587 bağlantısını test edin.'
printf '%s\n' '- SMTP açık relay testini yapın; yalnız SASL kimlik doğrulamalı gönderime izin verin.'
printf '%s\n' '- SPF, DKIM, DMARC, PTR/rDNS ve sertifika adlarını doğrulayın.'
printf '%s\n' '- Rspamd panelini ve yönetim portlarını internete açmayın.'
