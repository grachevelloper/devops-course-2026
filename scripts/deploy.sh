#!/usr/bin/env bash
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

DRY_RUN=false
case "$#:$*" in
    0:) ;;
    1:--dry-run) DRY_RUN=true ;;
    *) fail "Использование: scripts/deploy.sh [--dry-run]" ;;
esac

ROOT=$(git rev-parse --show-toplevel) || fail "Команда должна выполняться внутри репозитория"
LOCAL_DIR="$ROOT/site/"
[[ -f "$LOCAL_DIR/index.html" ]] || fail "Нет site/index.html: доставка отменена"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || fail "Есть незафиксированные изменения: доставка отменена"
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD)

RSYNC_ARGS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if $DRY_RUN; then
    RSYNC_ARGS+=(--dry-run)
fi

if ! rsync "${RSYNC_ARGS[@]}" "$LOCAL_DIR" "$REMOTE:$REMOTE_DIR/"; then
    fail "Ошибка доставки"
fi

if ! $DRY_RUN; then
    if ! curl --fail --silent --show-error --connect-timeout 10 --max-time 20 \
        --cacert "$CA_CERT" "$SITE_URL" > /dev/null; then
        fail "Доставка выполнена, но HTTPS-проверка не пройдена"
    fi
fi

printf 'Коммит %s: успешно\n' "$COMMIT"
