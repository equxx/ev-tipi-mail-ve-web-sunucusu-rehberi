#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }
warn() { printf 'UYARI: %s\n' "$*" >&2; }

[[ "${EUID}" -eq 0 ]] || die 'Bu betik root olarak çalıştırılmalı (sudo).'
[[ $# -eq 1 ]] || { printf 'Kullanım: sudo %s /path/to/server.env\n' "$0"; exit 2; }
env_file="$1"
[[ -f "$env_file" ]] || die "Config bulunamadı: $env_file"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${MAIL_DOMAIN:?MAIL_DOMAIN eksik}"
: "${MAIL_HOSTNAME:?MAIL_HOSTNAME eksik}"
: "${LAN_CIDR:?LAN_CIDR eksik}"
[[ "$MAIL_DOMAIN" != 'example.com' ]] || die 'Önce gerçek alan adını yazın.'
[[ "$MAIL_HOSTNAME" != 'mail.example.com' ]] || die 'Önce gerçek mail hostname’ini yazın.'
for dns_name in "$MAIL_DOMAIN" "$MAIL_HOSTNAME"; do
    [[ "$dns_name" =~ ^[A-Za-z0-9.-]+$ ]] || die "Geçersiz DNS adı: $dns_name"
done

for required_command in postconf doveconf systemctl install cp; do
    command -v "$required_command" >/dev/null 2>&1 || die "$required_command bulunamadı. Önce install-linux.sh çalıştırın."
done

backup_root="/var/backups/linux-ev-sunucusu/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_root"
for config_path in \
    /etc/postfix/main.cf \
    /etc/postfix/master.cf \
    /etc/dovecot/conf.d/10-mail.conf \
    /etc/dovecot/conf.d/10-auth.conf \
    /etc/dovecot/conf.d/10-master.conf; do
    if [[ -f "$config_path" ]]; then
        cp -a "$config_path" "$backup_root/"
    fi
done

# Tek alan adlı, yerel sistem kullanıcılarının Maildir kutularını kullanan taban.
postconf -e "myhostname = $MAIL_HOSTNAME"
postconf -e "mydomain = $MAIL_DOMAIN"
postconf -e 'myorigin = $mydomain'
postconf -e 'inet_interfaces = all'
postconf -e 'inet_protocols = all'
postconf -e 'home_mailbox = Maildir/'
postconf -e 'mynetworks = 127.0.0.0/8, [::1]/128'
postconf -e 'mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain'
postconf -e 'smtpd_helo_required = yes'
postconf -e 'disable_vrfy_command = yes'
postconf -e 'smtpd_tls_security_level = may'
postconf -e 'smtpd_tls_auth_only = yes'
postconf -e 'smtpd_sasl_type = dovecot'
postconf -e 'smtpd_sasl_path = private/auth'
postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination'
postconf -e 'smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination'
postconf -e 'smtpd_milters = inet:127.0.0.1:11332'
postconf -e 'non_smtpd_milters = inet:127.0.0.1:11332'
postconf -e 'milter_default_action = accept'
postconf -e 'milter_protocol = 6'

# Dovecot ayarları ayrı local dosyada tutulur; dağıtımın örnek dosyaları ezilmez.
cat > /etc/dovecot/conf.d/99-home-server-mail.conf <<'DOVECOT_MAIL'
mail_location = maildir:~/Maildir
auth_mechanisms = plain login
disable_plaintext_auth = yes
DOVECOT_MAIL

cat > /etc/dovecot/conf.d/99-home-server-postfix-auth.conf <<'DOVECOT_AUTH'
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
DOVECOT_AUTH

# Submission portunu yalnız TLS ve SASL ile aç. postconf -P eski sürümlerde olmayabilir.
if postconf -P >/dev/null 2>&1; then
    postconf -M 'submission/inet=submission inet n - y - - smtpd'
    postconf -P 'submission/inet/syslog_name=postfix/submission'
    postconf -P 'submission/inet/smtpd_tls_security_level=encrypt'
    postconf -P 'submission/inet/smtpd_sasl_auth_enable=yes'
    postconf -P 'submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject'
else
    warn 'Bu Postfix sürümü postconf -P desteklemiyor; 587 submission ayarını master.cf içinde elle açın.'
fi

if [[ -n "${TLS_CERT_FILE:-}" && -n "${TLS_KEY_FILE:-}" ]]; then
    [[ -f "$TLS_CERT_FILE" ]] || die "TLS sertifikası bulunamadı: $TLS_CERT_FILE"
    [[ -f "$TLS_KEY_FILE" ]] || die "TLS anahtarı bulunamadı: $TLS_KEY_FILE"
    postconf -e "smtpd_tls_cert_file = $TLS_CERT_FILE"
    postconf -e "smtpd_tls_key_file = $TLS_KEY_FILE"
else
    warn 'TLS_CERT_FILE/TLS_KEY_FILE boş; Postfix sistem sertifikasıyla başlayabilir. Geçerli alan adı sertifikası alınca server.env’i doldurup bu betiği tekrar çalıştırın.'
fi

postfix check
doveconf -n >/dev/null
systemctl enable --now redis-server rspamd dovecot postfix
systemctl restart dovecot postfix

printf '\nMail tabanı uygulandı. Yedek: %s\n' "$backup_root"
printf '%s\n' 'Henüz DKIM anahtarı veya posta hesabı oluşturulmadı; bunları gerçek alan adı ve parola politikasıyla ayrı adımda yapın.'
printf '%s\n' 'Açık relay kontrolü: postconf smtpd_relay_restrictions'
