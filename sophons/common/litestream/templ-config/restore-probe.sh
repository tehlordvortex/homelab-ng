#!/bin/bash
. /etc/litestream/common.sh

if test -z "${LITESTREAM_NO_REPLICATE:-}" && socket_exists; then exit 0; fi

is_restore_from_config_complete "$CONFIG_PATH"
if test -z "${LITESTREAM_NO_REPLICATE:-}"; then socket_exists; fi
clear_restored_flags_from_config "$CONFIG_PATH"
