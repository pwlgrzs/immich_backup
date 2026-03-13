#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/backup.log"
START_TIME=$(date +%s)

# Load Telegram helper
source /usr/local/bin/notify.sh

# Trap for failure notifications
trap 'FAILED_STEP="${BASH_COMMAND}"; \
    END_TIME=$(date +%s); \
    DURATION=$((END_TIME - START_TIME)); \
    echo "[$(date)] ERROR: Backup failed at step: ${FAILED_STEP}"; \
    telegram_notify "$(printf "<b>❌ Immich Backup FAILED</b>\n\n<b>Failed at:</b> <code>%s</code>\n<b>Duration:</b> %ss\n<b>Time:</b> %s" \
        "${FAILED_STEP}" "${DURATION}" "$(date)")"; \
    exit 1' ERR

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

DB_SIZE=$(du -sh "${UPLOAD_LOCATION}/database-backup/immich-database.sql" | cut -f1)

# Initialize borg repo if it doesn't exist yet
if [ ! -d "${BACKUP_PATH}/immich-borg" ]; then
    echo "[$(date)] Initializing Borg repository..."
    borg init --encryption=repokey-blake2 "${BACKUP_PATH}/immich-borg"
    echo "[$(date)] IMPORTANT: Run 'borg key export' to back up your repository key!"
fi

# Create borg archive
echo "[$(date)] Creating Borg archive..."
BORG_OUTPUT=$(borg create \
    --compression zstd,3 \
    --lock-wait 60 \
    --stats \
    --show-rc \
    "${BACKUP_PATH}/immich-borg::{now}" \
    "${UPLOAD_LOCATION}" \
    --exclude "${UPLOAD_LOCATION}/thumbs/" \
    --exclude "${UPLOAD_LOCATION}/encoded-video/" 2>&1)

echo "$BORG_OUTPUT"

# Parse borg stats
ORIGINAL_SIZE=$(echo "$BORG_OUTPUT" | grep "This archive:" | awk '{print $3, $4}')
DEDUP_SIZE=$(echo "$BORG_OUTPUT" | grep "This archive:" | awk '{print $NF-1, $NF}' || echo "N/A")

# Verify database dump is present in the archive
echo "[$(date)] Verifying database dump in Borg archive..."
LATEST_ARCHIVE=$(borg list --last 1 --short "${BACKUP_PATH}/immich-borg")

if borg list "${BACKUP_PATH}/immich-borg::${LATEST_ARCHIVE}" | grep -q "immich-database.sql"; then
    echo "[$(date)] Verification passed: immich-database.sql found in ${LATEST_ARCHIVE}."
else
    echo "[$(date)] ERROR: immich-database.sql NOT found in Borg archive!" >&2
    exit 1
fi

# Build prune arguments dynamically
PRUNE_ARGS=""

if [ "${KEEP_DAILY:-0}" -gt 0 ]; then
    PRUNE_ARGS="$PRUNE_ARGS --keep-daily=${KEEP_DAILY}"
fi

if [ "${KEEP_WEEKLY:-0}" -gt 0 ]; then
    PRUNE_ARGS="$PRUNE_ARGS --keep-weekly=${KEEP_WEEKLY}"
fi

if [ "${KEEP_MONTHLY:-0}" -gt 0 ]; then
    PRUNE_ARGS="$PRUNE_ARGS --keep-monthly=${KEEP_MONTHLY}"
fi

if [ -z "$PRUNE_ARGS" ]; then
    echo "[$(date)] WARNING: No prune rules defined, skipping prune step."
else
    echo "[$(date)] Pruning Borg archives (daily=${KEEP_DAILY:-0} weekly=${KEEP_WEEKLY:-0} monthly=${KEEP_MONTHLY:-0})..."
    borg prune $PRUNE_ARGS "${BACKUP_PATH}/immich-borg"
fi
# Compact repository
echo "[$(date)] Compacting Borg repository..."
borg compact "${BACKUP_PATH}/immich-borg"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "[$(date)] Backup finished successfully in ${DURATION}s."

# Success notification
telegram_notify "$(printf "<b>✅ Immich Backup Successful</b>\n\n<b>Archive:</b> <code>%s</code>\n<b>DB dump size:</b> %s\n<b>Duration:</b> %ss\n<b>Time:</b> %s" \
    "${LATEST_ARCHIVE}" \
    "${DB_SIZE}" \
    "${DURATION}" \
    "$(date)")"
