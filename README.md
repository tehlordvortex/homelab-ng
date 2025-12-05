# Me Homelabby Lab

hello there!
this is my current repo where i'm basically going all in on [Talos](https://talos.dev/) and [K8s](https://kubernetes.io/) bare-metal/VM nodes for my homelab.

[Cilium](https://cilium.io) is my current CNI of choice, with cross-node connectivity running over [Tailscale](https://tailscale.com), connected to an in-cluster [Headscale](https://headscale.net) instance.

Initial cluster setup was done with KubeSpan and flannel, before migrating to Cilium, and then Cilium + Tailscale.

I use [Traefik](https://traefik.io/) as my Ingress/Gateway, and I have Cloudflare in front of most of these.
For direct TCP/UDP connectivity, I use [MetalLB](https://metallb.io/) with IPv6 subnets from my hosting provider and primary ISP, and a subnet of my home IPv4 network for "internal" stuff.

My [previous setup](https://github.com/tehlordvortex/homelab) (repo horribly out of date) was a mix of Proxmox, Ansible (for managing hosts, LXC containers, and docker compose setups), and then eventually some LXC containers running k3s+flannel on Debian 12 (with a set of Fly.io machines running an etcd cluster), all connected over Tailscale.

### Nodes

my setup is uhh, a bit jank:

- unifi for networking (1g), starlink primary isp, mtn ng fallback isp (ipv4 only :()
- 1.5 RPi4's, in my house - `beta` and `prime`
- 1 vm and 1 container, on my desktop (surprise, also in my house) - `kaos` and `caeneus`
  - container shares gpu with host
- a tiny vps in NG - `oduduwa`
- a less tiny vps in NL - `theta`

### TODO

- Migrate vps in DE to Talos
- Migrate second RPi4 to Talos
- Setup ArgoCD
