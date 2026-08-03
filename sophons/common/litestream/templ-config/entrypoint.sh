#!/bin/bash
. /etc/litestream/common.sh

: "${LITESTREAM_CONFIG:?}"

render >"$CONFIG_PATH" <<EOF
$(cat "$BASE_CONFIG_PATH")

${LITESTREAM_CONFIG}
EOF

restore_from_config "$CONFIG_PATH"
do_startup_actions
if test -z "${LITESTREAM_NO_REPLICATE:-}"; then
  exec litestream replicate -config="$CONFIG_PATH"
else
  exec sleep infinity
fi
