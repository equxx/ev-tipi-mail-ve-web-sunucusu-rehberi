#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != "--apply" ]]; then
    printf '%s\n' \
        "Bu işlem yerel Docker veri klasörlerini ve rastgele veritabanı parolalarını oluşturur." \
        "Çalıştırmak için: ./scripts/prepare-docker-data.sh --apply"
    exit 0
fi

cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
    printf '%s\n' ".env bulunamadı. Önce: cp .env.example .env" >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    printf '%s\n' "openssl gerekli; Linux sisteminizin paket yöneticisiyle kurun." >&2
    exit 1
fi

umask 077
mkdir -p \
    docker-data/dms/config \
    docker-data/dms/mail-data \
    docker-data/dms/mail-state \
    docker-data/dms/mail-logs \
    docker-data/dms/certs \
    docker-data/roundcube/db \
    docker-data/roundcube/config \
    docker-data/roundcube/temp \
    docker-data/nginx

if [[ ! -f docker-data/dms/mailserver.env ]]; then
    cp docker-data/dms/mailserver.env.example docker-data/dms/mailserver.env
fi

if [[ ! -f docker-data/nginx/default.conf ]]; then
    cp docker-data/nginx/default.conf.example docker-data/nginx/default.conf
fi

if [[ ! -f docker-data/roundcube/db.env ]]; then
    db_root_password="$(openssl rand -hex 24)"
    db_password="$(openssl rand -hex 24)"
    printf 'MARIADB_ROOT_PASSWORD=%s\nMARIADB_DATABASE=roundcube\nMARIADB_USER=roundcube\nMARIADB_PASSWORD=%s\n' \
        "$db_root_password" "$db_password" > docker-data/roundcube/db.env
fi

if [[ ! -f docker-data/roundcube/roundcube.env ]]; then
    db_password="$(awk -F= '$1 == "MARIADB_PASSWORD" { print substr($0, index($0, "=") + 1) }' docker-data/roundcube/db.env)"
    if [[ -z "$db_password" ]]; then
        printf '%s\n' "db.env içinde MARIADB_PASSWORD bulunamadı." >&2
        exit 1
    fi
    printf 'ROUNDCUBEMAIL_DB_TYPE=mysql\nROUNDCUBEMAIL_DB_HOST=db\nROUNDCUBEMAIL_DB_PORT=3306\nROUNDCUBEMAIL_DB_USER=roundcube\nROUNDCUBEMAIL_DB_PASSWORD=%s\nROUNDCUBEMAIL_DB_NAME=roundcube\n' \
        "$db_password" > docker-data/roundcube/roundcube.env
fi

chmod 600 docker-data/dms/mailserver.env docker-data/roundcube/db.env docker-data/roundcube/roundcube.env
printf '%s\n' "Docker veri klasörleri hazır. Mevcut gizli dosyaların üzerine yazılmadı."
