# immich-backup

> :warning: This project was created with AI assistance (Perplexity AI). Review all scripts before running in production.

A lightweight Docker container that automates [Immich](https://immich.app/) backups using `pg_dump` for the database and [BorgBackup](https://borgbackup.readthedocs.io/) for files. Built on Alpine Linux with `postgresql17-client` for full Immich DB compatibility.

## Features

- Scheduled backups via cron
- PostgreSQL database dump (`pg_dump`) into the upload location
- Borg incremental backup with `repokey-blake2` encryption and `zstd,3` compression
- DB dump integrity check before archiving
- Borg archive verification after each run
- Configurable retention policy (daily, weekly, monthly)
- Automatic pruning and compaction
- Persistent Borg cache across container recreations
- Log rotation (last 1000 lines retained)
- Read-only upload mount for security
- Telegram notifications on success and failure
- Excludes regeneratable data (`thumbs/`, `encoded-video/`)

## Requirements

- Docker & Docker Compose
- A running Immich instance
- Borg repository storage location (local or mounted remote)

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/pwlgrzs/immich_backup.git
cd immich_backup
```

### 2. Configure environment

```bash
cp .env.example .env
```

| Variable              | Description                                          | Example                    |
|-----------------------|------------------------------------------------------|----------------------------|
| `DB_HOST`             | PostgreSQL host                                      | `your.remote.db.host`      |
| `DB_PORT`             | PostgreSQL port                                      | `5432`                     |
| `DB_NAME`             | Database name                                        | `immich`                   |
| `DB_USER`             | Database user                                        | `immich`                   |
| `DB_PASSWORD`         | Database password                                    | `secret`                   |
| `UPLOAD_LOCATION`     | Path to Immich uploads directory                     | `/mnt/data/immich/uploads` |
| `BACKUP_PATH`         | Path to store Borg repository                        | `/mnt/backup`              |
| `CRON_SCHEDULE`       | Cron expression for backup schedule                  | `0 2 * * *`                |
| `BORG_PASSPHRASE`     | Passphrase for Borg encryption                       | `your_strong_passphrase`   |
| `KEEP_DAILY`          | Number of daily archives to keep (`0` to disable)    | `7`                        |
| `KEEP_WEEKLY`         | Number of weekly archives to keep (`0` to disable)   | `4`                        |
| `KEEP_MONTHLY`        | Number of monthly archives to keep (`0` to disable)  | `3`                        |
| `TELEGRAM_BOT_TOKEN`  | Telegram bot token (optional)                        | `123456:ABCDEF...`         |
| `TELEGRAM_CHAT_ID`    | Telegram chat ID (optional)                          | `123456789`                |

### 3. Build and start

```bash
docker compose up -d --build
```

On first run, the Borg repository is initialized automatically at `$BACKUP_PATH/immich-borg` with `repokey-blake2` encryption.

### 4. :warning: Back up your Borg key

After the first run, immediately export and store your Borg repository key in a safe place. Without it, your backups cannot be decrypted:

```bash
# Encrypted binary (most compact)
docker compose exec immich-backup \
    borg key export "${BACKUP_PATH}/immich-borg" /tmp/immich-borg-key.enc

# Plain text / paper backup
docker compose exec immich-backup \
    borg key export --paper "${BACKUP_PATH}/immich-borg" /tmp/immich-borg-key.txt

# QR code HTML (easy to print and scan)
docker compose exec immich-backup \
    borg key export --qr-html "${BACKUP_PATH}/immich-borg" /tmp/immich-borg-key.html
```

Then copy the exported files from the container to your host:

```bash
docker cp immich-backup:/tmp/immich-borg-key.enc ./immich-borg-key.enc
docker cp immich-backup:/tmp/immich-borg-key.txt ./immich-borg-key.txt
docker cp immich-backup:/tmp/immich-borg-key.html ./immich-borg-key.html
```

Store these files — along with your `BORG_PASSPHRASE` — in a safe place **separate from the backup drive** (e.g. password manager, printed paper, secondary storage).

## Manual Backup

```bash
docker compose exec immich-backup /usr/local/bin/backup.sh
```

## View Logs

```bash
docker compose logs -f immich-backup
# or inside the container:
docker compose exec immich-backup tail -f /var/log/backup.log
```

## Restore

### Database

```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME < /path/to/immich-database.sql
```

### Files

```bash
borg list $BACKUP_PATH/immich-borg
borg extract $BACKUP_PATH/immich-borg::ARCHIVE_NAME
```

## :speech_balloon: Telegram Notifications

The backup container can send Telegram notifications on every backup run, including job duration, database dump size, archive name, and failure details with the exact failed step.

### Setup

1. Message [@BotFather](https://t.me/BotFather) on Telegram and run `/newbot` to create a bot — copy the token it provides
2. Message [@userinfobot](https://t.me/userinfobot) to retrieve your personal chat ID
3. Add both values to your `.env`:

```env
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

Notifications are optional — if either variable is missing from `.env`, the backup runs normally and silently skips the Telegram step.

### Notification Examples

**Success:**
```
✅ Immich Backup Successful

Archive: 2026-03-13T16:00:01
DB dump size: 244M
Duration: 312s
Time: Fri Mar 13 16:05:13 UTC 2026
```

**Failure:**
```
❌ Immich Backup FAILED

Failed at: pg_dump ...
Duration: 8s
Time: Fri Mar 13 16:00:09 UTC 2026
```

## Docker Image

Pre-built images are available via GitHub Container Registry:

```bash
docker pull ghcr.io/pwlgrzs/immich_backup:latest
```

## What Is Backed Up

| Path | Backed up | Reason |
|---|---|---|
| `$UPLOAD_LOCATION` (all files) | :white_check_mark: | Original uploads |
| `$UPLOAD_LOCATION/database-backup/` | :white_check_mark: | DB dump included in borg archive |
| `$UPLOAD_LOCATION/thumbs/` | :x: | Regeneratable by Immich |
| `$UPLOAD_LOCATION/encoded-video/` | :x: | Regeneratable by Immich |

## License

MIT
