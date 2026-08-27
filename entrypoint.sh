#!/bin/bash
set -euo pipefail

# Apply timezone from TZ env var (passed via docker-compose .env)
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    cp "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
elif [ -n "${TZ:-}" ]; then
    echo "WARNING: TZ='${TZ}' not found in /usr/share/zoneinfo, using UTC."
fi

PUID=${PUID:-1000}
PGID=${PGID:-1000}

echo "Starting with UID: ${PUID}, GID: ${PGID}"

# Create group if it doesn't exist
if ! getent group "${PGID}" > /dev/null 2>&1; then
    groupadd -g "${PGID}" backupgroup
fi

# Create user if it doesn't exist
if ! getent passwd "${PUID}" > /dev/null 2>&1; then
    useradd -u "${PUID}" -g "${PGID}" -d /home/backupuser -s /bin/bash -M backupuser
fi

# Ensure cache directory exists and is owned correctly
mkdir -p /home/backupuser/.cache/borg
chown -R "${PUID}:${PGID}" /home/backupuser/.cache/borg

# Ensure log file exists and is writable
touch /var/log/backup.log
chown "${PUID}:${PGID}" /var/log/backup.log

# Export env vars for cron.
# cron runs with an empty environment, so the backup job sources this file.
# Use `printf %q` so values containing spaces or shell metacharacters
# (e.g. paths like "/mnt/my backups", or a passphrase with symbols) survive
# being sourced back in.
: > /etc/backup-env
chmod 600 /etc/backup-env
env | grep -E '^(DB_|UPLOAD_LOCATION|BACKUP_PATH|BORG_|TZ|TELEGRAM_|KEEP_|FULL_BACKUP)=' | \
    while IFS='=' read -r k v; do
        printf 'export %s=%q\n' "$k" "$v"
    done >> /etc/backup-env

# Always write crontab as root — Alpine dcron requires root-owned crontab files.
# NOTE: the backup job currently runs as root (not PUID/PGID); files it writes
# into UPLOAD_LOCATION/database-backup will be root-owned.
# Run the job through bash so the `printf %q` quoting in /etc/backup-env parses.
mkdir -p /etc/crontabs
echo "${CRON_SCHEDULE} /bin/bash -c '. /etc/backup-env && exec /usr/local/bin/backup.sh' >> /var/log/backup.log 2>&1" \
    > /etc/crontabs/root
chmod 600 /etc/crontabs/root
chown root:root /etc/crontabs/root

# Verify
echo "Crontab contents:"
cat /etc/crontabs/root
echo "Crontab ownership:"
ls -la /etc/crontabs/root

echo "Cron schedule set to: ${CRON_SCHEDULE}"
echo "Starting cron daemon..."

touch /var/log/backup.log

# crond is the process that must keep the container alive. Run tail in the
# background for log visibility, but wait on crond so that if it ever dies the
# container exits (and `restart: unless-stopped` brings it back) instead of
# silently sitting there with no scheduler running.
crond -f -l 6 &
CROND_PID=$!

tail -f /var/log/backup.log &
TAIL_PID=$!

trap 'kill "${CROND_PID}" "${TAIL_PID}" 2>/dev/null || true' TERM INT

if wait "${CROND_PID}"; then
    CROND_RC=0
else
    CROND_RC=$?
fi
echo "crond exited with rc=${CROND_RC}, shutting down."
kill "${TAIL_PID}" 2>/dev/null || true
exit "${CROND_RC}"