#!/bin/bash
set -xeuo pipefail

self_path=$(readlink -f "$0")
self_dir=$(dirname $self_path)
skip_address_prefixes='["fdf6:9420:fade:ffff:","2606:4700:","172.16.0.2"]'
internal_address_prefixes='["100.","fd7a:115c:a1e0:"]'

mise talos:all get nodeaddresses current-no-k8s -o json |
  jq -s --argjson skip $skip_address_prefixes \
    '{nodes: [.[] | select(.node != env.SOPHONS_PRIME) | .spec.addresses[] | split("/") | .[0] | select(. as $v | reduce $skip.[] as $s (true; . and ($v | startswith($s) | not))) | {address: .}]}' |
  tee $self_dir/nodes.sops.json
jq --argjson internal $internal_address_prefixes '{nodes: [.nodes[] | select(.address as $a | reduce $internal.[] as $i (false; . or ($a | startswith($i))))]}' <$self_dir/nodes.sops.json |
  tee $self_dir/nodes.internal.sops.json
