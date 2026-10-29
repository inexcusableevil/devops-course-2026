#!/usr/bin/env bash
# Доставка статического ресурса: scripts/deploy.sh [--dry-run]
set -euo pipefail
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_DIR}/site/"
DRY_RUN=false
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --dry-run ) ]]; then
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
fi
[[ $# -eq 1 ]] && DRY_RUN=true
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: отсутствует site/index.html; доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения; доставка отменена" >&2
    exit 1
fi
OPTIONS=(-avz --delete --chmod=D755,F644)
$DRY_RUN && OPTIONS+=(--dry-run)
if ! rsync "${OPTIONS[@]}" -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка синхронизации" >&2
    exit 1
fi
if $DRY_RUN; then
    echo "Пробный запуск: состояние сервера не изменено"
    exit 0
fi
if ! curl -4 --fail --silent --show-error --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" --output /dev/null "$SITE_URL"; then
    echo "Ошибка: проверка HTTPS после доставки не пройдена" >&2
    exit 1
fi
echo "Доставлен коммит $(git -C "$REPO_DIR" rev-parse --short HEAD)"
