#!/bin/bash
. /etc/litestream/common.sh

: "${LITESTREAM_CONFIG:?}"

render >"$CONFIG_PATH" <<EOF
$(cat "$BASE_CONFIG_PATH")

${LITESTREAM_CONFIG}
EOF

# bg & wait combo for signal forwarding
install_trap
restore_from_config "$CONFIG_PATH" &
child=$!
wait
do_startup_actions &
child=$!
wait
uninstall_trap

if test -z "${LITESTREAM_NO_REPLICATE:-}"; then
  exec litestream replicate -config="$CONFIG_PATH"
else
  exec sleep infinity
fi
