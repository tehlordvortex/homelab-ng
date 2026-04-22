#!/bin/bash
. /etc/litestream/common.sh

export LITESTREAM_REPLICA_URL="$(replica_url)"

: "${LITESTREAM_REPLICA_URL:?}"
: "${LITESTREAM_DBS:?}"
: "${LITESTREAM_DBS_DIR:?}"
: "${LITESTREAM_DBS_PATTERN:?}"

IFS=","
for db in $LITESTREAM_DBS; do
  db_path="$LITESTREAM_DBS_DIR/$db"
  db_uri="$(replica_url "$db")"

  restore "$db_path" "$db_uri"
done

if test -z "${LITESTREAM_NO_REPLICATE:-}"; then
  exec litestream replicate -config=/etc/litestream/litestream-watch.yaml
else
  exec sleep infinity
fi
