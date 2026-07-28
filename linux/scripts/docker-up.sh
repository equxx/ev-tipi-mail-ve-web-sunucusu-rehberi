#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

case "${1:-}" in
    ""|--apply) ;;
    *)
        printf '%s\n' "Kullanım: ./scripts/docker-up.sh [--apply]" >&2
        exit 2
        ;;
esac

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' "Docker bulunamadı. Önce Docker Engine ve Compose V2 kurun." >&2
    exit 1
fi

if [[ ! -f .env ]]; then
    printf '%s\n' ".env bulunamadı. Önce: cp .env.example .env" >&2
    exit 1
fi

for required_file in \
    docker-data/dms/mailserver.env \
    docker-data/roundcube/db.env \
    docker-data/roundcube/roundcube.env \
    docker-data/nginx/default.conf; do
    if [[ ! -f "$required_file" ]]; then
        printf '%s\n' "$required_file bulunamadı. Önce ./scripts/prepare-docker-data.sh --apply çalıştırın." >&2
        exit 1
    fi
done

if ! docker compose version >/dev/null 2>&1; then
    printf '%s\n' "Docker Compose V2 bulunamadı; 'docker compose version' kontrolünü yapın." >&2
    exit 1
fi

# config --quiet yalnızca Compose dosyasını çözümler; image indirmez veya container başlatmaz.
docker compose config --quiet
printf '%s\n' "Compose yapılandırması geçerli."

if [[ "${1:-}" != "--apply" ]]; then
    printf '%s\n' "Container başlatılmadı. Başlatmak için: ./scripts/docker-up.sh --apply"
    exit 0
fi

printf '%s\n' "Image'lar indiriliyor; yalnızca Docker'ın kendi veri alanı değiştirilecek."
docker compose pull
docker compose up -d
printf '%s\n' "Container'lar başlatıldı. Durum için: ./scripts/docker-check.sh"
