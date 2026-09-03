#!/bin/bash
set -euo pipefail

self_path=$(readlink -f "$0")
self_dir=$(dirname $self_path)
alias curl="curl -qsS"

cf_v4="$(curl https://www.cloudflare.com/ips-v4 | sort)"
cf_v6="$(curl https://www.cloudflare.com/ips-v6 | sort)"
cf_ips="$cf_v4
$cf_v6"

bunny_v4="$(curl https://bunnycdn.com/api/system/edgeserverlist | jq -r '.[] | . + "/32"' | sort)"
bunny_v6="$(curl https://bunnycdn.com/api/system/edgeserverlist/IPv6 | jq -r '.[] | . + "/128"' | sort)"
bunny_ips="$bunny_v4
$bunny_v6"

tee "$self_dir/ciliumcidrgroup.generated.yaml" <<EOT
apiVersion: cilium.io/v2
kind: CiliumCIDRGroup
metadata:
  name: cloudflare
spec:
  externalCIDRs:
$(sed 's/^/    - /' <<<"$cf_ips")
---
apiVersion: cilium.io/v2
kind: CiliumCIDRGroup
metadata:
  name: bunny
spec:
  externalCIDRs:
$(sed 's/^/    - /' <<<"$bunny_ips")
EOT

tee "$self_dir/values.trusted-ips.generated.yaml" <<EOT
ports:
  websecure:
    forwardedHeaders:
      trustedIPs:
        # - 10.67.0.0/16
        # - fdf6:9420:fade::/48
        - 10.41.0.0/16
        - 2001:cafe:41::/56
$(sed 's/^/        - /' <<<"$cf_ips")
$(sed 's/^/        - /' <<<"$bunny_ips")
EOT
