#!/bin/bash
. /etc/litestream/common.sh

: "${LITESTREAM_DB_PATH:?}"

is_restore_complete "$LITESTREAM_DB_PATH"
clear_restored_flag "$LITESTREAM_DB_PATH"
