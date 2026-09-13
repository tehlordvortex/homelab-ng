#!/bin/ash
set -euo pipefail

alias jq="/jq/jq"
alias bcurl="curl -sS -H 'accesskey: $API_KEY'"
crt="$(cat /cert/tls.crt | base64 -w0)"
key="$(cat /cert/tls.key | base64 -w0)"

# echo "set ipFamilyPolicy: DualStackPreferIPv6 (2)"
echo "set ipFamilyPolicy: DualStack (1)"
bcurl -X POST --url "https://api.bunny.net/pullzone/$PULL_ZONE_ID" \
  -H 'content-type: application/json' -d '{"IpFamilyPolicy":1}' >/tmp/pz.json

echo "syncing ceritifcates and hostnames for pull zone: $PULL_ZONE_ID"
# bcurl "https://api.bunny.net/pullzone/$PULL_ZONE_ID" > /tmp/pz.json
jq -r '.Hostnames[].Value' /tmp/pz.json | while read -r host; do
  if echo "$host" | grep -qE '\.(b-cdn\.net|bunny\.run)$'; then
    echo "skip $host, managed by bunny"
    continue
  fi

  if ! grep -qxF "DNS:$host" /tmp/sans.txt; then
    echo "remove $host from pull zone"

    bcurl -X DELETE --url "https://api.bunny.net/pullzone/$PULL_ZONE_ID/removeHostname" \
      -H 'content-type: application/json' -d '{"Hostname":"'$host'"}'
  fi
done

cat /tmp/sans.txt | while read -r san; do
  host="${san#'DNS:'}"
  if ! jq -e --arg host "$host" '.Hostnames | any(.Value == $host)' /tmp/pz.json >/dev/null; then
    echo "add $host to pull zone"

    bcurl -X POST --url "https://api.bunny.net/pullzone/$PULL_ZONE_ID/addHostname" \
      -H 'content-type: application/json' -d '{"Hostname":"'$host'"}'
  fi

  echo "sync certificate for $host"

  bcurl -X POST --url "https://api.bunny.net/pullzone/$PULL_ZONE_ID/addCertificate" \
    -H 'content-type: application/json' \
    -d '{"Hostname":"'$host'","Certificate":"'$crt'","CertificateKey":"'$key'"}'

  force_ssl="$(jq -r --arg host "$host" '.Hostnames[] | select(.Value == $host) | .ForceSSL' /tmp/pz.json)"
  if [ "$force_ssl" != "true" ]; then
    echo "enable force ssl for $host"

    bcurl -X POST --url "https://api.bunny.net/pullzone/$PULL_ZONE_ID/setForceSSL" \
      -H 'content-type: application/json' -d '{"Hostname":"'$host'","ForceSSL":true}'
  fi
done

echo done
