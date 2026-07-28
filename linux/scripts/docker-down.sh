#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

case "${1:-}" in
    ""|--apply) ;;
    *)
        printf '%s\n' "Kullanım: ./scripts/docker-down.sh [--apply]" >&2
        exit 2
        ;;
esac

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' "Docker bulunamadı." >&2
    exit 1
fi

if [[ "${1:-}" != "--apply" ]]; then
    printf '%s\n' \
        "Container'lar durdurulacak; docker-data içindeki veriler silinmeyecek." \
        "Gerçekten durdurmak için: ./scripts/docker-down.sh --apply"
    exit 0
fi

docker compose down
printf '%s\n' "Container'lar durduruldu; kalıcı veriler korunuyor."
