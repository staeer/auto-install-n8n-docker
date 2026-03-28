#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

[[ -f "$ENV_FILE" ]] || { echo ".env not found: $ENV_FILE"; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

BACKUP_DIR="${INSTALL_DIR}/backups"
DATE="$(date +%Y%m%d_%H%M%S)"
FILE="$BACKUP_DIR/n8n_pg_$DATE.sql.gz"

mkdir -p "$BACKUP_DIR"
docker exec n8n_postgres pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "$FILE"
ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo "Backup saved: $FILE"
