#!/bin/ash
set -euo pipefail
sigterm=15
sigint=2

apk add --no-cache haproxy

cleanup() {
  echo -n "received signal $@, shutting down..."

  kill -$sigterm $haproxy
  wait $haproxy

  echo " done."
  exit 0
}
trap 'cleanup' $sigterm $sigint

# Claude mostly wrote this, hallucinated support for UDP where non existed /shrug
haproxy -f - <<EOF
global
    daemon
    log stdout

defaults
    mode tcp
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend 80
    bind *:80
    server traefik traefik:80 send-proxy-v2

frontend 443
    bind *:443
    server traefik traefik:443 send-proxy-v2
EOF
$haproxy=$?

wait $haproxy
