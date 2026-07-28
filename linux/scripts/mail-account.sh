#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' "Docker bulunamadı." >&2
    exit 1
fi

read -r -p "E-posta adresi (ör. kullanici@alan-adiniz): " address
if [[ ! "$address" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
    printf '%s\n' "Geçerli bir e-posta adresi girin." >&2
    exit 1
fi

printf '%s\n' "Parolayı docker-mailserver istemi isteyecek; parola bu betikte saklanmaz."
docker compose exec mail setup email add "$address"
