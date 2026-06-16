#!/bin/sh

set -xeuo pipefail

self_path=$(readlink -f "$0")
self_dir=$(dirname $self_path)
patch_dir=$self_dir/patches

cluster=sophons
endpoint=$SOPHONS_ENDPOINT_URL
talos_version=$TALOS_VERSION
kubernetes_version=v1.36.1

vm_image=af87088cf1b22437863dea5433e70768e92cd109a7b115161490f2abf15c26ab
pi_image=c00a850feae6a2eeabc0168e1ca0d15c24f8d7ce474fdb1155a16d3b8d4ec3bb
prime_image=f2ebdd5b4b64f7acdfb0edbb88969872f52f7ad605ef5158db43d4b9e21a8b24

gen_controlplane() {
  local host_name=$1
  local image=$2

  gen_wgcf $host_name "$patch_dir/wg.cf.sops.yaml"
  gen_wg $host_name "$patch_dir/wg.kluster.sops.yaml"

  talosctl gen config $cluster $endpoint \
    --force --with-examples=false \
    --install-image=$image \
    --talos-version=$talos_version \
    --kubernetes-version=$kubernetes_version \
    --with-secrets "$self_dir/secrets.yaml" \
    --config-patch "@$patch_dir/common.sops.yaml" \
    --config-patch "@$patch_dir/chrome.seccomp.yaml" \
    --config-patch "@$patch_dir/controlplane.sops.yaml" \
    --config-patch "@$patch_dir/$host_name.sops.yaml" \
    --config-patch "@$self_dir/generated/wg.cf.$host_name.yaml" \
    --config-patch "@$self_dir/generated/wg.kluster.$host_name.yaml" \
    --output-types controlplane \
    --output "$self_dir/generated/controlplane.$host_name.yaml"

  talosctl machineconfig patch \
    "$self_dir/generated/controlplane.$host_name.yaml" \
    --patch "@$patch_dir/allow-controlplane-lb.yaml" \
    --output "$self_dir/generated/controlplane.$host_name.yaml"
}

gen_worker() {
  local host_name=$1
  local image=$2

  gen_wgcf $host_name "$patch_dir/wg.cf.sops.yaml"
  gen_wg $host_name "$patch_dir/wg.kluster.sops.yaml"

  talosctl gen config $cluster $endpoint \
    --force --with-examples=false \
    --install-image=$image \
    --talos-version=$talos_version \
    --kubernetes-version=$kubernetes_version \
    --with-secrets "$self_dir/secrets.yaml" \
    --config-patch "@$patch_dir/common.sops.yaml" \
    --config-patch "@$patch_dir/chrome.seccomp.yaml" \
    --config-patch "@$patch_dir/$host_name.sops.yaml" \
    --config-patch "@$self_dir/generated/wg.cf.$host_name.yaml" \
    --config-patch "@$self_dir/generated/wg.kluster.$host_name.yaml" \
    --output-types worker \
    --output "$self_dir/generated/worker.$host_name.yaml"
}

gen_wg() {
  local host_name="$1"
  local config="$2"
  local interface="$(basename "$config" | sed s/.sops.yaml$//)"
  local enriched="$self_dir/generated/$interface.yaml"

  local name
  cp "$config" "$enriched"
  for name in $(yq '.peers | keys | .[]' "$enriched"); do
    pubkey=$(yq ".wireguard.privateKeys.$name" "$enriched" | wg pubkey)
    yq --inplace ".peers.$name.publicKey = \"$pubkey\"" $enriched
  done

  HOST_NAME="$host_name" INTERFACE="$interface" yq '
    env(HOST_NAME) as $selfName |
    .peers[$selfName] as $self  |
    .wireguard as $wg |
    [.peers | to_entries[] | select(.key != $selfName)] as $peers |
    {
      "apiVersion": "v1alpha1",
      "kind": "WireguardConfig",
      "name": env(INTERFACE),
      "up": true,
      "mtu": $wg.mtu,
      "privateKey": $wg.privateKeys[$selfName],
      "listenPort": $wg.listenPort,
      "addresses": [$self.addresses[] | {"address": .}],
      "peers": [
        $peers[] | .key as $peerName | .value as $peer |
        ([$selfName, $peerName] | sort | join(":")) as $pairKey |
        {
          "publicKey": $peer.publicKey,
          "presharedKey": $wg.presharedKeys[$pairKey],
          "allowedIPs": ($peer.addresses + $peer.allowedIPs)
        } |
        # skip endpoint only when peer is behind a NAT and we arent
        with(select($peer.nat == false or $self.nat == true);
          .endpoint = (($peer.endpoints[($self.via // "v4")] // $peer.endpoints.v4) + ":" + ($wg.listenPort | tostring))
        ) |
        with(select(($self.persistentKeepaliveInterval // "") != "");
          .persistentKeepaliveInterval = $self.persistentKeepaliveInterval
        )
      ],
      "routes": [$peers[].value | (.addresses + .allowedIPs + (.routes // []))[] | {"destination": .}]
    }
  ' "$enriched" >"$self_dir/generated/$interface.$host_name.yaml"
}

gen_wgcf() {
  local host_name="$1"
  local config="$2"
  local interface="$(basename "$config" | sed s/.sops.yaml$//)"
  local has_interface="$(HOST_NAME="$host_name" yq '.nodes[env(HOST_NAME)] != null' "$config")"

  HOST_NAME="$host_name" INTERFACE="$interface" yq '
    .wireguard as $wg |
    .nodes[env(HOST_NAME)] as $self |
    {
      "apiVersion": "v1alpha1",
      "kind": "WireguardConfig",
      "name": env(INTERFACE),
      "up": false,
      "mtu": $wg.mtu,
      "listenPort": $wg.listenPort,
      "privateKey": $wg.placeholderPrivateKey,
      "peers": [{
        "publicKey": $wg.publicKey,
        "allowedIPs": ["0.0.0.0/0", "::/0"],
        "endpoint": $wg.endpoint
      } |
      with(select($self.persistentKeepaliveInterval != null);
        .persistentKeepaliveInterval = $self.persistentKeepaliveInterval
      )]
    } * ((select($self != null) | {
      "up": true,
      "privateKey": $self.privateKey,
      "addresses": [$self.addresses[] | {"address": .}],
      "routes": [{"gateway":  "fe80::1", "metric": 256}]
    }))
  ' "$config" >"$self_dir/generated/$interface.$host_name.yaml"
}

rm -r $self_dir/generated
mkdir -p $self_dir/generated

gen_controlplane beta factory.talos.dev/installer/$pi_image:$talos_version
gen_controlplane theta factory.talos.dev/installer/$vm_image:$talos_version
gen_controlplane voltzahl factory.talos.dev/installer/$vm_image:$talos_version

gen_worker alpha factory.talos.dev/installer/$pi_image:$talos_version
gen_worker prime factory.talos.dev/installer/$prime_image:$talos_version
gen_worker oduduwa factory.talos.dev/installer/$vm_image:$talos_version
gen_worker caeneus ghcr.io/siderolabs/talos:$talos_version
