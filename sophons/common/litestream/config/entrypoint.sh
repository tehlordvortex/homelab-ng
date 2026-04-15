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
: "${LITESTREAM_DB_PATH:?}"

if test -z "${LITESTREAM_NO_RESTORE:-}"; then
  rm -f $LITESTREAM_DB_PATH
  LITESTREAM_LOGGING_LEVEL=debug litestream restore \
    -config=/etc/litestream/litestream.yaml -if-replica-exists \
    $LITESTREAM_DB_PATH
fi

# initialize db as litestream user if it doesn't exist
sqlite3 $LITESTREAM_DB_PATH "PRAGMA journal_mode=WAL;"
exec litestream replicate -config=/etc/litestream/litestream.yaml
