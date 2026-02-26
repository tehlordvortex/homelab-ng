#!/bin/sh

set -xeuo pipefail

self_path=$(readlink -f "$0")
self_dir=$(dirname $self_path)
patch_dir=$self_dir/patches

cluster=sophons
endpoint=$SOPHONS_ENDPOINT_URL
talos_version=$TALOS_VERSION
kubernetes_version=v1.34.1

vm_image=992627e65361721c9e2b8ee8423120d4435e6e8561bc2b03224642181c0a2bcd
pi_image=587b98cabc477550e3ae6703e244ee20378357b698c921dbe6acf980dc9be34c
prime_image=b5021510b89077fd40ed47244165a9aa628491d603b32a7478c251852e943565

gen_controlplane() {
  local host_name=$1
  local image=$2

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

  talosctl gen config $cluster $endpoint \
    --force --with-examples=false \
    --install-image=$image \
    --talos-version=$talos_version \
    --kubernetes-version=$kubernetes_version \
    --with-secrets "$self_dir/secrets.yaml" \
    --config-patch "@$patch_dir/common.sops.yaml" \
    --config-patch "@$patch_dir/chrome.seccomp.yaml" \
    --config-patch "@$patch_dir/$host_name.sops.yaml" \
    --output-types worker \
    --output "$self_dir/generated/worker.$host_name.yaml"
}

mkdir -p $self_dir/generated
rm -r $self_dir/generated/*.yaml

gen_controlplane beta factory.talos.dev/installer/$pi_image:$talos_version
gen_controlplane theta factory.talos.dev/installer/$vm_image:$talos_version
gen_controlplane voltzahl factory.talos.dev/installer/$vm_image:$talos_version

gen_worker alpha factory.talos.dev/installer/$pi_image:$talos_version
gen_worker prime factory.talos.dev/installer/$prime_image:$talos_version
gen_worker oduduwa factory.talos.dev/installer/$vm_image:$talos_version
gen_worker caeneus ghcr.io/siderolabs/talos:$talos_version
