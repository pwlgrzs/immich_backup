#!/bin/bash
set -euo pipefail

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

BACKUP_USER=$(getent passwd "${PUID}" | cut -d: -f1)

# Ensure cache directory exists and is owned correctly
mkdir -p /home/backupuser/.cache/borg
chown -R "${PUID}:${PGID}" /home/backupuser/.cache/borg

# Ensure log file exists and is writable
touch /var/log/backup.log
chown "${PUID}:${PGID}" /var/log/backup.log

# Export env vars for cron
env | grep -E '^(DB_|UPLOAD_LOCATION|BACKUP_PATH|BORG_|TZ|TELEGRAM_|KEEP_|PU)' > /etc/backup-env
chmod 600 /etc/backup-env

# Write crontab for the backup user
mkdir -p /etc/crontabs
# Clear any previous entry and write fresh
echo "${CRON_SCHEDULE} . /etc/backup-env && /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" \
    > "/etc/crontabs/${BACKUP_USER}"
chmod 600 "/etc/crontabs/${BACKUP_USER}"
chown "${PUID}:${PGID}" "/etc/crontabs/${BACKUP_USER}"

# Verify the crontab was written correctly
echo "Crontab contents:"
cat "/etc/crontabs/${BACKUP_USER}"

echo "Cron schedule set to: ${CRON_SCHEDULE}"
echo "Starting cron daemon..."

touch /var/log/backup.log
crond -f -l 6 &
tail -f /var/log/backup.log