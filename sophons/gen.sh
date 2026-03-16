#!/bin/sh

set -xeuo pipefail

self_path=$(readlink -f "$0")
self_dir=$(dirname $self_path)
patch_dir=$self_dir/patches

cluster=sophons
endpoint=$SOPHONS_ENDPOINT_URL
talos_version=$TALOS_VERSION
kubernetes_version=v1.35.2

vm_image=af87088cf1b22437863dea5433e70768e92cd109a7b115161490f2abf15c26ab
pi_image=c37ef14b65c7f5cb5d59ca8c4e4d724b046d26792822f121cdf06f1e237b947b
prime_image=31f689a89d04e3f459a4e9fff089a5e9f2cf2d1ba119488c6dad9d6f9dee8a8b

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
rm -rf $self_dir/generated/*.yaml

gen_controlplane beta factory.talos.dev/installer/$pi_image:$talos_version
gen_controlplane theta factory.talos.dev/installer/$vm_image:$talos_version
gen_controlplane voltzahl factory.talos.dev/installer/$vm_image:$talos_version

gen_worker alpha factory.talos.dev/installer/$pi_image:$talos_version
gen_worker prime factory.talos.dev/installer/$prime_image:$talos_version
gen_worker oduduwa factory.talos.dev/installer/$vm_image:$talos_version
gen_worker caeneus ghcr.io/siderolabs/talos:$talos_version
