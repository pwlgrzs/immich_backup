FROM alpine:3.21

RUN apk add --no-cache \
    borgbackup \
    postgresql17-client \
    dcron \
    bash \
    tzdata \
    wget

COPY backup.sh /usr/local/bin/backup.sh
COPY notify.sh /usr/local/bin/notify.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/notify.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
