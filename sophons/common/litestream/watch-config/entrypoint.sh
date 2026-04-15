#!/bin/sh
set -xeu

replica_url() {
  local db=${1:-}

  if test -n "${LITESTREAM_BUCKET:-}"; then
    printf "s3://$LITESTREAM_BUCKET/$LITESTREAM_REPLICA_PATH/$db?endpoint=$LITESTREAM_ENDPOINT&region=${LITESTREAM_REGION:-}&force-path-style=true"
  else
    printf "file://$LITESTREAM_REPLICA_PATH/$db"
  fi
}
export LITESTREAM_REPLICA_URL="$(replica_url)"

: "${LITESTREAM_REPLICA_URL:?}"
: "${LITESTREAM_DBS:?}"
: "${LITESTREAM_DBS_DIR:?}"
: "${LITESTREAM_DBS_PATTERN:?}"

IFS=","
for db in $LITESTREAM_DBS; do
  db_path="$LITESTREAM_DBS_DIR/$db"
  db_uri="$(replica_url $db)"

  if test -z "${LITESTREAM_NO_RESTORE:-}"; then
    rm -f "$db_path"
    LITESTREAM_LOGGING_LEVEL=debug litestream restore -if-replica-exists \
      -o "$db_path" "$db_uri"
  fi

  # initialize db as litestream user if it doesn't exist
  sqlite3 $db_path "PRAGMA journal_mode=WAL;"
done

exec litestream replicate -config=/etc/litestream/litestream.yaml
