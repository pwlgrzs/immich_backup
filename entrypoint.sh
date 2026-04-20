#!/bin/bash
set -euo pipefail

# Apply timezone from TZ env var (passed via docker-compose .env)
if [ -n "${TZ}" ]; then
    cp "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
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

# Export env vars for cron
env | grep -E '^(DB_|UPLOAD_LOCATION|BACKUP_PATH|BORG_|TZ|TELEGRAM_|KEEP_|FULL_BACKUP)' > /etc/backup-env
chmod 600 /etc/backup-env

# Always write crontab as root — Alpine dcron requires root-owned crontab files
# The backup script itself uses PUID/PGID for filesystem access via su-exec
mkdir -p /etc/crontabs
echo "${CRON_SCHEDULE} . /etc/backup-env && /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" \
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
crond -f -l 6 &
tail -f /var/log/backup.log