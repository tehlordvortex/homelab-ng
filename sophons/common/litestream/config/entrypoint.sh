#!/bin/bash
. /etc/litestream/common.sh
export LITESTREAM_REPLICA_URL="$(replica_url)"

: "${LITESTREAM_REPLICA_URL:?}"
: "${LITESTREAM_DB_PATH:?}"

restore "$LITESTREAM_DB_PATH" "$LITESTREAM_REPLICA_URL"

if test -z "${LITESTREAM_NO_REPLICATE:-}"; then
  exec litestream replicate -config=/etc/litestream/litestream.yaml
else
  exec sleep infinity
fi
