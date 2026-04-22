#!/bin/bash
. /etc/litestream/common.sh

: "${LITESTREAM_DBS:?}"
: "${LITESTREAM_DBS_DIR:?}"

IFS=","
for db in $LITESTREAM_DBS; do
  db_path="$LITESTREAM_DBS_DIR/$db"

  is_restore_complete "$db_path"
done
for db in $LITESTREAM_DBS; do
  db_path="$LITESTREAM_DBS_DIR/$db"

  clear_restored_flag "$db_path"
done
