#!/bin/bash
set -euo pipefail

echo "[$(date)] Starting Immich backup..."

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

# Initialize borg repo if it doesn't exist yet
if [ ! -d "${BACKUP_PATH}/immich-borg" ]; then
    echo "[$(date)] Initializing Borg repository..."
    borg init --encryption=none "${BACKUP_PATH}/immich-borg"
fi

# Create borg archive
echo "[$(date)] Creating Borg archive..."
borg create \
    "${BACKUP_PATH}/immich-borg::{now}" \
    "${UPLOAD_LOCATION}" \
    --exclude "${UPLOAD_LOCATION}/thumbs/" \
    --exclude "${UPLOAD_LOCATION}/encoded-video/" \
    --stats \
    --show-rc

# Prune old archives
echo "[$(date)] Pruning Borg archives..."
borg prune \
    --keep-weekly=4 \
    --keep-monthly=3 \
    "${BACKUP_PATH}/immich-borg"

# Compact repository
echo "[$(date)] Compacting Borg repository..."
borg compact "${BACKUP_PATH}/immich-borg"

echo "[$(date)] Backup finished successfully."
