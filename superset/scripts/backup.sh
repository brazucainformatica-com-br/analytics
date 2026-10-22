#!/usr/bin/env bash
# Backup dos metadados do LineaSuite BI (painéis, gráficos, usuários, regras de RLS) e do .env.
# Os dados do ERP não estão aqui: continuam no backup da MariaDB.
set -euo pipefail
APP_DIR="/opt/lineasuite-bi"
DEST="/var/backups/lineasuite-bi"
STAMP="$(date +%Y%m%d-%H%M)"
umask 077
mkdir -p "$DEST"
docker exec bi_db pg_dump -U superset -d superset -Fc > "$DEST/superset-$STAMP.dump"
cp "$APP_DIR/.env" "$DEST/env-$STAMP"
find "$DEST" -type f -mtime +14 -delete
ls -lh "$DEST" | tail -n 4
