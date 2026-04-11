#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/backup.log"
START_TIME=$(date +%s)

source /usr/local/bin/notify.sh

trap 'FAILED_STEP="${BASH_COMMAND}"; \
    END_TIME=$(date +%s); \
    DURATION=$((END_TIME - START_TIME)); \
    echo "[$(date)] ERROR: Backup failed at step: ${FAILED_STEP}"; \
    telegram_notify "$(printf "<b>❌ Immich DB Backup FAILED</b>\n\n<b>Failed at:</b> <code>%s</code>\n<b>Duration:</b> %ss\n<b>Time:</b> %s" \
        "${FAILED_STEP}" "${DURATION}" "$(date)")"; \
    exit 1' ERR

echo "[$(date)] Starting Immich database-only backup..."

mkdir -p "${UPLOAD_LOCATION}/database-backup"

echo "[$(date)] Dumping database..."
PGPASSWORD="${DB_PASSWORD}" pg_dump \
    --clean \
    --if-exists \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    > "${UPLOAD_LOCATION}/database-backup/immich-database.sql"

if [ ! -s "${UPLOAD_LOCATION}/database-backup/immich-database.sql" ]; then
    echo "[$(date)] ERROR: Database dump is empty or missing!" >&2
    exit 1
fi

DB_SIZE=$(du -sh "${UPLOAD_LOCATION}/database-backup/immich-database.sql" | cut -f1)
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "[$(date)] Database dump complete. Size: ${DB_SIZE}, Duration: ${DURATION}s"

telegram_notify "$(printf "<b>✅ Immich DB Dump Successful</b>\n\n<b>DB dump size:</b> %s\n<b>Duration:</b> %ss\n<b>Time:</b> %s" \
    "${DB_SIZE}" \
    "${DURATION}" \
    "$(date)")"