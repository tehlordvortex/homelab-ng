FROM docker.io/library/alpine:3.24.1 AS redis-s3-sync
RUN apk add --no-cache inotify-tools aws-cli zstd
ADD s3.sh /sbin/s3.sh
ENTRYPOINT [ "/sbin/s3.sh" ]
