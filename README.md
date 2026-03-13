# immich-backup

> ⚠️ This project was created with AI assistance (Perplexity AI). Review all scripts before running in production.

A lightweight Docker container that automates [Immich](https://immich.app/) backups using `pg_dump` for the database and [BorgBackup](https://borgbackup.readthedocs.io/) for files. Built on Alpine Linux with `postgresql17-client` for full Immich DB compatibility.

## Features

- Scheduled backups via cron
- PostgreSQL database dump (`pg_dump`) into the upload location
- Borg incremental backup of the upload directory
- Automatic pruning (4 weekly, 3 monthly) and compaction
- Excludes regeneratable data (`thumbs/`, `encoded-video/`)

## Requirements

- Docker & Docker Compose
- A running Immich instance
- Borg repository storage location (local or mounted remote)

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
```

### 2. Configure environment

Copy and edit the example env file:

```bash
cp .env.example .env
```

| Variable          | Description                              | Example                    |
|-------------------|------------------------------------------|----------------------------|
| `DB_HOST`         | PostgreSQL host                          | `your.remote.db.host`      |
| `DB_PORT`         | PostgreSQL port                          | `5432`                     |
| `DB_NAME`         | Database name                            | `immich`                   |
| `DB_USER`         | Database user                            | `immich`                   |
| `DB_PASSWORD`     | Database password                        | `secret`                   |
| `UPLOAD_LOCATION` | Path to Immich uploads directory         | `/mnt/data/immich/uploads` |
| `BACKUP_PATH`     | Path to store Borg repository            | `/mnt/backup`              |
| `CRON_SCHEDULE`   | Cron expression for backup schedule      | `0 2 * * *`                |

### 3. Build and start

```bash
docker compose up -d --build
```

On first run, the Borg repository is initialized automatically at `$BACKUP_PATH/immich-borg`.

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

## Docker Image

Pre-built images are available via GitHub Container Registry:

```bash
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO:main
```

## What Is Backed Up

| Path | Backed up | Reason |
|---|---|---|
| `$UPLOAD_LOCATION` (all files) | ✅ | Original uploads |
| `$UPLOAD_LOCATION/database-backup/` | ✅ | DB dump included in borg |
| `$UPLOAD_LOCATION/thumbs/` | ❌ | Regeneratable by Immich |
| `$UPLOAD_LOCATION/encoded-video/` | ❌ | Regeneratable by Immich |

## License

MIT
