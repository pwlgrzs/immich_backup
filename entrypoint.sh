#!/bin/bash
set -euo pipefail
export TZ="${TZ:-UTC}"

# Export env vars for cron (dcron doesn't inherit them automatically)
env | grep -E '^(DB_|UPLOAD_LOCATION|BACKUP_PATH)' > /etc/backup-env

# Write cron job using the schedule from env
echo "${CRON_SCHEDULE} . /etc/backup-env && /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" \
    > /etc/crontabs/root

echo "Cron schedule set to: ${CRON_SCHEDULE}"
echo "Starting cron daemon..."

# Tail log alongside cron so Docker logs are useful
touch /var/log/backup.log
crond -f -l 6 &
tail -f /var/log/backup.log
