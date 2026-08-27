#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/backup.log"
START_TIME=$(date +%s)

source /usr/local/bin/notify.sh

# Single failure path for both the ERR trap (unexpected command failure) and
# explicit `fail` calls (checks that detected a problem). Guarded so it only
# ever notifies once.
FAILURE_NOTIFIED=0
notify_failure() {
    [ "${FAILURE_NOTIFIED}" -eq 1 ] && return
    FAILURE_NOTIFIED=1
    local failed_step="$1"
    local now duration
    now=$(date +%s)
    duration=$((now - START_TIME))
    echo "[$(date)] ERROR: Backup failed at step: ${failed_step}"
    telegram_notify "$(printf "<b>❌ Immich Backup FAILED</b>\n\n<b>Failed at:</b> <code>%s</code>\n<b>Duration:</b> %ss\n<b>Time:</b> %s" \
        "${failed_step}" "${duration}" "$(date)")"
}

fail() {
    notify_failure "$1"
    exit 1
}

trap 'notify_failure "${BASH_COMMAND}"; exit 1' ERR

# Route to DB-only if FULL_BACKUP=0
FULL_BACKUP=${FULL_BACKUP:-1}
if [ "${FULL_BACKUP}" = "0" ]; then
    echo "[$(date)] FULL_BACKUP=0, running database-only backup..."
    exec /usr/local/bin/db-only-backup.sh
fi

echo "[$(date)] Starting Immich full backup..."

# Log rotation: keep last 1000 lines
if [ -f "$LOG_FILE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

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

echo "[$(date)] Database dump complete."

if [ ! -s "${UPLOAD_LOCATION}/database-backup/immich-database.sql" ]; then
    fail "Database dump is empty or missing"
fi
echo "[$(date)] Database dump integrity check passed."

DB_SIZE=$(du -sh "${UPLOAD_LOCATION}/database-backup/immich-database.sql" | cut -f1)

if [ ! -d "${BACKUP_PATH}/immich-borg" ]; then
    echo "[$(date)] Initializing Borg repository..."
    borg init --encryption=repokey-blake2 "${BACKUP_PATH}/immich-borg"
    echo "[$(date)] IMPORTANT: Run 'borg key export' to back up your repository key!"
fi

echo "[$(date)] Creating Borg archive..."
# borg exit codes: 0 = success, 1 = warning (e.g. a file changed or vanished
# mid-read, which is normal on a live Immich upload dir), >=2 = error.
# Temporarily disable set -e so a benign rc=1 doesn't abort the whole run.
set +e
BORG_OUTPUT=$(borg create \
    --compression zstd,3 \
    --lock-wait 60 \
    --stats \
    --show-rc \
    "${BACKUP_PATH}/immich-borg::{now}" \
    "${UPLOAD_LOCATION}" \
    --exclude "${UPLOAD_LOCATION}/thumbs/" \
    --exclude "${UPLOAD_LOCATION}/encoded-video/" 2>&1)
BORG_RC=$?
set -e

echo "$BORG_OUTPUT"

if [ "${BORG_RC}" -ge 2 ]; then
    fail "borg create failed (rc=${BORG_RC})"
elif [ "${BORG_RC}" -eq 1 ]; then
    echo "[$(date)] WARNING: borg create completed with warnings (rc=1), continuing."
fi

echo "[$(date)] Verifying database dump in Borg archive..."
LATEST_ARCHIVE=$(borg list --last 1 --short "${BACKUP_PATH}/immich-borg")

if borg list "${BACKUP_PATH}/immich-borg::${LATEST_ARCHIVE}" | grep -q "immich-database.sql"; then
    echo "[$(date)] Verification passed: immich-database.sql found in ${LATEST_ARCHIVE}."
else
    fail "immich-database.sql NOT found in Borg archive"
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
    set +e
    borg prune $PRUNE_ARGS "${BACKUP_PATH}/immich-borg"
    PRUNE_RC=$?
    set -e
    if [ "${PRUNE_RC}" -ge 2 ]; then
        fail "borg prune failed (rc=${PRUNE_RC})"
    elif [ "${PRUNE_RC}" -eq 1 ]; then
        echo "[$(date)] WARNING: borg prune completed with warnings (rc=1), continuing."
    fi
fi

echo "[$(date)] Compacting Borg repository..."
set +e
borg compact "${BACKUP_PATH}/immich-borg"
COMPACT_RC=$?
set -e
if [ "${COMPACT_RC}" -ge 2 ]; then
    fail "borg compact failed (rc=${COMPACT_RC})"
elif [ "${COMPACT_RC}" -eq 1 ]; then
    echo "[$(date)] WARNING: borg compact completed with warnings (rc=1), continuing."
fi

# Stats are best-effort: borg's "info" output format varies between versions,
# so a missing line must not trigger the ERR trap after a successful backup.
BORG_INFO=$(borg info "${BACKUP_PATH}/immich-borg" 2>&1 || true)
REPO_LINE=$(echo "$BORG_INFO" | grep "All archives:" || true)
REPO_ORIGINAL=$(echo "$REPO_LINE" | awk '{print $3, $4}')
REPO_COMPRESSED=$(echo "$REPO_LINE" | awk '{print $5, $6}')
REPO_DEDUP=$(echo "$REPO_LINE" | awk '{print $7, $8}')
ARCHIVE_COUNT=$(borg list --short "${BACKUP_PATH}/immich-borg" 2>/dev/null | wc -l | tr -d ' ' || true)

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "[$(date)] Backup finished successfully in ${DURATION}s."

telegram_notify "$(printf \
"<b>✅ Immich Backup Successful</b>

<b>Archive:</b> <code>%s</code>
<b>DB dump size:</b> %s
<b>Duration:</b> %ss

<b>📦 Repository Stats</b>
<b>Total archives:</b> %s
<b>Original size:</b> %s
<b>Compressed size:</b> %s
<b>Deduplicated size:</b> %s

<b>Time:</b> %s" \
    "${LATEST_ARCHIVE}" \
    "${DB_SIZE}" \
    "${DURATION}" \
    "${ARCHIVE_COUNT}" \
    "${REPO_ORIGINAL}" \
    "${REPO_COMPRESSED}" \
    "${REPO_DEDUP}" \
    "$(date)")"