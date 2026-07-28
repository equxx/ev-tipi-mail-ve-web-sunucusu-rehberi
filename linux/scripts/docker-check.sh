#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' "Docker bulunamadı." >&2
    exit 1
fi

docker compose config --quiet
printf '%s\n' "Container durumu:"
docker compose ps
printf '%s\n' "Image durumu:"
docker compose images
