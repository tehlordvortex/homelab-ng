#!/bin/bash
. /etc/litestream/common.sh

is_restore_from_config_complete "$CONFIG_PATH"
if test -z "${LITESTREAM_NO_REPLICATE:-}"; then
  [ -S "$LITESTREAM_SOCKET_PATH" ]
fi
clear_restored_flags_from_config "$CONFIG_PATH"
