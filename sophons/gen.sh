#!/bin/sh

set -xeuo pipefail

self_path=$(readlink -f "$0")
self_dir=$(dirname $self_path)
patch_dir=$self_dir/patches

cluster=sophons
endpoint=$SOPHONS_ENDPOINT_URL
talos_version=v1.11.3
kubernetes_version=v1.34.1
# pi_image=008ccc3eef3828058d2b4030ce83c192f2abe193dde422349b3621c44228d659
# vm_image=ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
pi_image=5a73dbaa7dff12395f0e502b57b443242f737816f7350aec31ecd2f6f07b0796
vm_image=53513e54bb39202f35694412577a6bc53d484744d35a126e5d42ef34785c0d83
prime_image=5ecf11c5535b8698f995a8f21e0d38650c813f9eabe9bb33d2237d1bd039cdb1
# prime_image=fb3ac4c237f50886fb0da70b3db82d056503af58a2ceb004bd55bfc0f219f1f8

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
gen_controlplane kaos factory.talos.dev/installer/$vm_image:$talos_version

gen_worker prime factory.talos.dev/installer/$prime_image:$talos_version
gen_worker oduduwa factory.talos.dev/installer/$vm_image:$talos_version
gen_worker caeneus ghcr.io/siderolabs/talos:v1.11.3
