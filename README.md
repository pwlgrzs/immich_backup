# pg-backup

A lightweight Docker container that runs scheduled PostgreSQL dumps from a remote server using `pg_dump` and `cron`.

> ?? This project was created with AI assistance (Perplexity AI).

## Features

- Connects to a **remote PostgreSQL server**
- Dumps a **single specified database**
- Runs on a **configurable cron schedule**
- Compresses output with `gzip`
- Filenames include **database name and timestamp**
- **Auto-cleans** backups older than 7 days
- All secrets managed via `.env`

## Requirements

- Docker & Docker Compose

## Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/pwlgrzs/db_backup.git
   cd db_backup
