#!/bin/bash

telegram_notify() {
    local MESSAGE="$1"
    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        echo "[$(date)] Telegram not configured, skipping notification."
        return
    fi
    wget -q -O /dev/null \
        --post-data="chat_id=${TELEGRAM_CHAT_ID}&text=${MESSAGE}&parse_mode=HTML" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
}
