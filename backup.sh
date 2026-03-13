#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/backup.log"
START_TIME=$(date +%s)

echo "[$(date)] Starting Immich backup..."

# Log rotation: keep last 1000 lines
if [ -f "$LOG_FILE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# Ensure backup directory exists
mkdir -p "${UPLOAD_LOCATION}/database-backup"

# Dump PostgreSQL database
echo "[$(date)] Dumping database..."
PGPASSWORD="${DB_PASSWORD}" pg_dump \
    --clean \
    --if-exists \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    > "${UPLOAD_LOCATION}/database-backup/immich-database.sql"

echo "[$(date)] Database dump complete."

# Integrity check: ensure dump is non-empty
if [ ! -s "${UPLOAD_LOCATION}/database-backup/immich-database.sql" ]; then
    echo "[$(date)] ERROR: Database dump is empty or missing!" >&2
    exit 1
fi
echo "[$(date)] Database dump integrity check passed."

# Initialize borg repo if it doesn't exist yet
if [ ! -d "${BACKUP_PATH}/immich-borg" ]; then
    echo "[$(date)] Initializing Borg repository..."
    borg init --encryption=repokey-blake2 "${BACKUP_PATH}/immich-borg"
    echo "[$(date)] IMPORTANT: Run 'borg key export' to back up your repository key!"
fi

# Create borg archive
echo "[$(date)] Creating Borg archive..."
borg create \
    --compression zstd,3 \
    --lock-wait 60 \
    --stats \
    --show-rc \
    "${BACKUP_PATH}/immich-borg::{now}" \
    "${UPLOAD_LOCATION}" \
    --exclude "${UPLOAD_LOCATION}/thumbs/" \
    --exclude "${UPLOAD_LOCATION}/encoded-video/"

# Verify database dump is present in the archive
echo "[$(date)] Verifying database dump in Borg archive..."
LATEST_ARCHIVE=$(borg list --last 1 --short "${BACKUP_PATH}/immich-borg")

if borg list "${BACKUP_PATH}/immich-borg::${LATEST_ARCHIVE}" | grep -q "immich-database.sql"; then
    echo "[$(date)] Verification passed: immich-database.sql found in ${LATEST_ARCHIVE}."
else
    echo "[$(date)] ERROR: immich-database.sql NOT found in Borg archive!" >&2
    exit 1
fi

# Prune old archives
echo "[$(date)] Pruning Borg archives..."
borg prune \
    --keep-weekly=4 \
    --keep-monthly=3 \
    "${BACKUP_PATH}/immich-borg"

# Compact repository
echo "[$(date)] Compacting Borg repository..."
borg compact "${BACKUP_PATH}/immich-borg"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "[$(date)] Backup finished successfully in ${DURATION}s."
