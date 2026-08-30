#!/bin/bash
set -xeuo pipefail
rtmp=/tmp/response
uerr="UNIQUE constraint failed"
perr="already present"
lan_caeneus=10.42.42.5
ts_caeneus=100.81.110.3
ts6_caeneus=fd7a:115c:a1e0:f742:2344:721:9806:34ed
lan_alpha=10.42.69.4
ts_alpha=100.100.27.65
ts6_alpha=fd7a:115c:a1e0:7c55:ba3c:60c8:a480:41f2
pub_voltzahl=$VOLTZAHL_V4
pub6_voltzahl=$VOLTZAHL_V6
ts_voltzahl=100.97.190.2
ts6_voltzahl=fd7a:115c:a1e0:fb03:7e99:473a:628f:35

until curl -sS -o- localhost/api/auth 2>&1 >/dev/null; do
  echo "waiting for pihole..."
  sleep 3
done

ctee() {
  local rc

  set +e
  curl --fail-with-body -sS "$@" 2>&1 >$rtmp
  rc=$?
  cat $rtmp

  if ! [ $rc -eq 0 ]; then
    grep "$uerr" $rtmp || grep "$perr" $rtmp
    rc=$?
  fi

  set -e
  return $rc
}

ctee localhost/api/groups -d '{
  "name": "lan",
  "comment": "devices querying via lan",
  "enabled": true
}'
ctee localhost/api/groups -d '{
  "name": "ts",
  "comment": "devices querying via tailscale",
  "enabled": true
}'

lan_id=$(curl -fsS localhost/api/groups/lan | jq '.groups[0].id')
ts_id=$(curl -fsS localhost/api/groups/ts | jq '.groups[0].id')
echo "lan: $lan_id tailscale: $ts_id"

ctee localhost/api/clients -d "{
  \"client\":[\"10.1.0.0/16\",\"10.42.0.0/16\",\"10.69.0.0/16\",\"10.67.0.103\",\"10.67.0.102\",\"10.67.0.105\",\"10.67.0.106\"],
  \"groups\":[0,$lan_id],
  \"comment\": \"lan ranges\"
}"
ctee localhost/api/clients -d "{
  \"client\":[\"100.64.0.0/10\",\"fd7a:115c:a1e0::/48\"],
  \"groups\":[0,$ts_id],
  \"comment\": \"tailscale ranges\"
}"

reply() {
  local group=$1
  local domain=$2
  local v4=$3
  local v6="${4:-::}"

  ctee localhost/api/domains/deny/regex -d "{
  \"domain\":\"$domain;reply=$v4;reply=$v6\",
  \"groups\":[$group],
  \"enabled\":true
}"
}

caeneus_domains='^((gimmich|neptune|sparrow|uwuget)\\.sophons\\.cloud|ic\\.vrtx\\.sh|(s3ui-global|p?s3-(backup|time-machine)|p?restic-(backup|time-machine))\\.sphns\\.run)$'
reply $lan_id $caeneus_domains $lan_caeneus
reply $ts_id $caeneus_domains $ts_caeneus $ts6_caeneus

voltzahl_domains='^(((ssh\\.)?tig|auth)\\.vrtx\\.sh|p?((s3|restic)-(global|weed|b2)|oci|z3)\\.sphns\\.run)$'
# for some reason, the first octet of the ipv4 address pihole returns when
# this is configured is wrong. the correct value is displayed in the UI. bug?
# reply $lan_id $voltzahl_domains $pub_voltzahl $pub6_voltzahl
reply $ts_id $voltzahl_domains $ts_voltzahl $ts6_voltzahl

alpha_domains='^(pds\\.vrtx\\.sh|(home|hoarder|positron|klstrmntr)\\.sophons\\.cloud)$'
reply $lan_id $alpha_domains $lan_alpha
reply $ts_id $alpha_domains $ts_alpha $ts6_alpha

ctee -XPOST localhost/api/action/restartdns

exec sleep infinity
