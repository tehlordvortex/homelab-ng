#!/bin/sh
set -euo pipefail
if [ -n "${DEBUG:-}" ]; then set -x; fi

: "${RDB_PATH:?}"
: "${S3_URI:?}"
: "${S3_ENDPOINT:?required}"

dir=$(dirname "$RDB_PATH")
base=$(basename "$RDB_PATH")
zstd_level=${ZSTD_COMPRESS:-9}

upload() {
  backoff=1
  rm -f "$RDB_PATH.zst"
  zstd -$zstd_level "$RDB_PATH"
  while ! aws s3 cp --endpoint-url "$S3_ENDPOINT" "$RDB_PATH.zst" "$S3_URI"; do
    echo "upload failed, retrying in ${backoff}s"
    sleep $backoff
    backoff=$((backoff * 2 > 180 ? backoff : backoff * 2))
  done
  rm -f "$RDB_PATH.zst"
  echo "snapshot sync - $RDB_PATH - $S3_URI"
}

mkdir -p "$dir"

set +e
if [ ! -f "$RDB_PATH" ]; then
  aws s3 ls --endpoint-url "$S3_ENDPOINT" "$S3_URI"
  rc=$?
  case $rc in
  0)
    set -e
    aws s3 cp --endpoint-url "$S3_ENDPOINT" "$S3_URI" "$RDB_PATH.zst"
    zstd --rm --decompress "$RDB_PATH.zst"
    echo "snapshot downloaded - $RDB_PATH - $S3_URI"
    ;;
  1) echo "no snapshot found - $RDB_PATH - $S3_URI" ;;
  *) exit $rc ;;
  esac
else
  set -e
  upload
fi
set -e

inotify_pid=
on_term() {
  echo "SIGTERM received, stopping inotifywait"
  [ -n $inotify_pid ] && kill $inotify_pid
}
trap on_term TERM

fifo="$dir/.$base.fifo"
if [ ! -e "$fifo" ]; then
  mkfifo "$fifo"
fi
inotifywait -m -e moved_to --format '%f' "$dir" >"$fifo" &
inotify_pid=$!

touch "$dir/.$base.ready"

while read -r file; do
  [ "$file" = "$base" ] || continue
  upload
done <"$fifo"

upload

wait $inotify_pid 2>/dev/null
inotify_rc=$?
rm -f "$fifo"
exit $inotify_rc
