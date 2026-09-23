#!/bin/sh
set -eu

kubectl get pods -o json -n kube-system \
  -l app.kubernetes.io/name=tailscale,app.kubernetes.io/instance=klusterscale |
  jq -r '.items[] | .metadata.name' |
  while read -r pod; do
    kubectl exec -n kube-system "pod/$pod" -- tailscale set \
      --advertise-exit-node=false --relay-server-port=41642
  done
