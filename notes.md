- IMPORTANT: <https://longhorn.io/docs/1.9.0/advanced-resources/os-distro-specific/talos-linux-support/#talos-linux-upgrades> - --preserve upgrades
- <https://github.com/siderolabs/talos/discussions/8037> - removing kube-proxy and flannel
  - `kubectl delete daemonset -n kube-system kube-flannel`
  - `kubectl delete daemonset -n kube-system kube-proxy`
  - `kubectl delete cm kube-flannel-cfg -n kube-system`
- Installing cilium:
  - <https://docs.cilium.io/en/stable/installation/k8s-install-migration/>
  - <https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium>
- <https://kubernetes.io/blog/2025/08/19/tuning-linux-swap-for-kubernetes-a-deep-dive/>
- CF IP ranges:
  - <https://www.cloudflare.com/ips-v6>
  - <https://www.cloudflare.com/ips-v4>
- `docker run --rm authelia/authelia:latest authelia crypto rand --length 72 --charset rfc3986`
  - <https://www.authelia.com/configuration/identity-providers/openid-connect/clients/>
  - `docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 64 --random.charset rfc3986 --iterations=100000`
- sysctl: user.max_user_namespaces must be > 0 for container inception.
  - todo: is this why chrome didn't work?
- <https://web.archive.org/web/20220805232857/https://home.robusta.dev/blog/stop-using-cpu-limits/>
- need to migrate all litestream instances to v0.3.13, v0.5.2 doesn't actually enforce retention:
  - <https://github.com/benbjohnson/litestream/blob/v0.5.2/replica.go#L230>
  - so it can grow infinitely, and restore time can get insane (i think this is due to the snapshot process being different too?)

#### manual etcd recovery without reset in case of data corruption

- pull ssd and run this on workstation or use `talosctl debug`: `while true; do pkill -9 -e etcd$; sleep 0.25; done` to shoot etcd whenever it tries to restart
- grab same etcd version from <https://github.com/etcd-io/etcd/releases>
- copy secrets from `/host/system/secrets/etcd` to `/tmp/secrets/etcd`, `chown 60:60 secrets`
- start etcd instance with user 60:60 in node-debugger container using, e.g.:

```sh
sudo -u etcd ./etcd2 --advertise-client-urls=https://node-a-ip:2379,https://node-a-ip2:2379 \
  --auto-tls=false --cert-file=/tmp/secrets/etcd/server.crt --client-cert-auth=true --data-dir=/tmp/etcd \
  --election-timeout=50000 --experimental-compact-hash-check-enabled=true --experimental-initial-corrupt-check=true \
  --experimental-watch-progress-notify-interval=5s --heartbeat-interval=5000 \
  --initial-advertise-peer-urls=https://node-a-ip:2380,https://node-a-ip2:2380 \
  --key-file=/tmp/secrets/etcd/server.key \
  --listen-client-urls=https://127.0.0.1:2379,https://node-a-ip:2379,https://node-a-ip2:2379 \
  --listen-peer-urls=https://node-a-ip:2380,https://node-a-ip2:2380 \
  --name=sophons-beta --peer-auto-tls=false --peer-cert-file=/tmp/secrets/etcd/peer.crt \
  --peer-client-cert-auth=true --peer-key-file=/tmp/secrets/etcd/peer.key  \
  --peer-trusted-ca-file=/tmp/secrets/etcd/ca.crt --trusted-ca-file=/tmp/secrets/etcd/ca.crt \
  --initial-cluster-state=existing \
  --initial-cluster="node-a=https://ip:2380,node-a=https://ip2:2380,node-b=https://ip:2380,node-b=https://ip2:2380"
```

- wait for etcd to publish member, download snapshot, sigint to trigger graceful shutdown
- swap in the fixed database:

```sh
pkill -9 -e etcd$ && mv /host/var/lib/etcd/member /tmp/etcd/member.old && mv /tmp/etcd/member /host/var/lib/etcd/member`

```

### resource adoption by helm

use `--take-ownership` or slap these bad bois on 'em:

```yaml
labels:
  - pairs:
      app.kubernetes.io/managed-by: Helm
commonAnnotations:
  meta.helm.sh/release-name: <name>
  meta.helm.sh/release-namespace: <namespace>
```
