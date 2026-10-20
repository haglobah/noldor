# Hyperscaler and serverless/container compute for Nix builds (October 2026)

Research date: 2026-10-12. All prices in USD as listed. Unless noted, "8/32" means 8 vCPU / 32 GiB. Per-hour figures marked "calc" are my arithmetic from cited unit prices.

Baseline for comparison (Cloudflare Containers standard-4, 4 vCPU / 12 GiB / 20 GB, at full CPU use): 4 x $0.000020 x 3600 = $0.288 CPU + 12 x $0.0000025 x 3600 = $0.108 memory + 20 x $0.00000007 x 3600 = $0.005 disk = **~$0.40/h, or $0.072 per vCPU-hour for CPU alone** (calc).

## AWS EC2, GCP and Azure: EU prices, spot, billing, storage, egress

### Takeaway
On-demand 8/32 ARM instances cost about $0.34–0.43/h in EU regions (~$0.04–0.054 per vCPU-hour). That is cheaper per vCPU than the Cloudflare baseline and has no 4 vCPU / 12 GiB / 20 GB ceiling. Spot/preemptible prices are typically 60–85% lower ($0.06–0.19/h). A persistent 200 GB SSD for /nix/store costs about $19–22/month on all three. These are full VMs, so the Nix sandbox and sshd work normally.

### Cited Findings
**AWS EC2, eu-central-1 (Frankfurt), Linux on-demand, AWS pricing feed published 2026-10-12T19:39Z** — [AWS pricing JSON (EU Frankfurt, Linux)](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/EU%20(Frankfurt)/Linux/index.json)
- m8g.2xlarge (Graviton4, 8/32): $0.43016/h → $0.0538 per vCPU-hour (calc)
- m7g.2xlarge (Graviton3, 8/32): $0.391/h
- m7i.2xlarge (8/32): $0.483/h; m8i.2xlarge (8/32): $0.50716/h
- m7a.2xlarge (8/32): $0.55544/h; m8a.2xlarge (8/32): $0.5832/h
- c8g.2xlarge (8/16): $0.3628/h; c7g.2xlarge (8/16): $0.3298/h
- c7a.2xlarge (8/16): $0.46852/h; c8a.2xlarge (8/16): $0.49196/h; c8i.2xlarge (8/16): $0.42776/h
- 16-vCPU options: c8g.4xlarge (16/32) $0.7256/h; m8g.4xlarge (16/64) $0.86032/h; c8a.4xlarge (16/32) $0.98392/h
- Note: the c-family 2xlarge sizes have 16 GiB, not 32. 8/32 means the m-family. c8g.4xlarge gives 16 vCPU / 32 GiB at $0.73/h.
- For comparison, Vantage shows m8g.2xlarge at $0.359/h on-demand, $0.117/h spot, $0.238/h 1-yr reserved, and $0.163/h 3-yr reserved. Vantage does not say which region, but the figures look like us-east-1, which is ~17% cheaper than Frankfurt. Page updated 2026-10-13. — [Vantage m8g.2xlarge](https://instances.vantage.sh/aws/ec2/m8g.2xlarge?region=eu-central-1)
- **Spot (AWS legacy spot-price feed, date not stated in the feed; treat as indicative):** eu-central-1 m7g.2xlarge $0.1852, m7a.2xlarge $0.0734, m7i.2xlarge $0.1937, c7g.2xlarge $0.1226, c7a.2xlarge $0.1621. eu-north-1 m7g.2xlarge $0.1169, m7a.2xlarge $0.0682. eu-west-1 m7g.2xlarge $0.1492. 8th-gen types are missing from this feed. — [AWS spot.js feed](https://spot-price.s3.amazonaws.com/spot.js)
- Billing: on-demand is billed "by the hour or second (minimum of 60 seconds)". Per-second billing covers Linux, Windows, RHEL and Ubuntu Pro. — [AWS EC2 on-demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- Egress: "100 GB of free data transfer out to the internet free each month", aggregated across services and regions. EU customers can request reduced rates under the EU Data Act. The page did not render the per-GB tier prices for Frankfurt. — [AWS EC2 on-demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- **EBS Frankfurt (same feed, 2026-10-12):** gp3 $0.0952/GB-month (200 GB ≈ $19.04/month calc). Extra gp3 IOPS cost $0.006/IOPS-month and extra throughput $48.74/GiBps-month. gp2 is $0.119. Snapshots are $0.054/GB-month. — [AWS EBS pricing JSON](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ebs.json)

**GCP**
- c4a-standard-8 (Axion ARM, 8 vCPU / 32 GB). Data updated 2026-10-11. — [gcloud-compute.com c4a-standard-8](https://gcloud-compute.com/c4a-standard-8.html)
  - europe-west4 (Netherlands): on-demand $0.3772/h, spot $0.0556/h (−85%)
  - europe-west3 (Frankfurt): on-demand $0.4239/h, spot $0.1651/h
  - europe-north1 (Finland): on-demand $0.3955/h, spot $0.0971/h
- pd-balanced in europe-west4: $0.11/GB-month (200 GB ≈ $22/month calc). The Hyperdisk Balanced price for europe-west4 was not shown. — [gcloud-compute.com hyperdisk-balanced / disk table](https://gcloud-compute.com/hyperdisk-balanced.html)
- Internet egress from Europe (third-party sources, not Google's page): Premium Tier is ~$0.12/GiB for the first TiB, then $0.11 and $0.085. Standard Tier is ~$0.085/GiB. Pricing depends on destination. — [zeroservices](https://lp.zeroservices.eu/articles/google-cloud-egress-pricing-2026/), [egresscost.com GCP regions](https://egresscost.com/gcp/regions). On 1 May 2026, Google reportedly raised peering and CDN Interconnect egress (Europe $0.05 → $0.08/GiB). Standard internet egress was not changed. — [egresscost.com](https://egresscost.com/gcp/peering-price-increase-2026)
- The official pages cloud.google.com/compute/disks-image-pricing and the VM pricing page did not render through the fetch tool.

**Azure, germanywestcentral, Linux pay-as-you-go, from the public Retail Prices API queried 2026-10-12** — [Azure Retail Prices API](https://prices.azure.com/api/retail/prices)
- D8ps_v6 (Cobalt 100 ARM, 8/32): $0.335/h; Spot $0.061908/h (−82%)
- D8pls_v6 (ARM, 8/16): $0.297/h; Spot $0.054886/h
- D8as_v6 / D8as_v7 (AMD, 8/32): $0.439/h; Spot $0.081127/h
- D8s_v6 (Intel, 8/32): $0.483/h; Spot $0.089258/h
- F8als_v6 (8/16): $0.585/h; Spot $0.108108/h
- Disks: Standard SSD E15 (256 GiB) $19.20/month; E10 (128 GiB) $9.60. Premium SSD P15 (256 GiB) $41.81; P10 $21.68. Premium SSD v2 $0.00013/GiB-hour (≈ $0.095/GiB-month calc).

### Inferences
- The cheapest on-demand 8/32 in the EU is Azure D8ps_v6 ($0.335/h), then GCP c4a-standard-8 europe-west4 ($0.377/h), then AWS m8g.2xlarge Frankfurt ($0.430/h). All three are aarch64. For x86_64, Azure D8as_v6/v7 ($0.439/h) is the cheapest found.
- Spot: GCP c4a europe-west4 ($0.056/h) and Azure D8ps_v6 ($0.062/h) cost about 7x less per hour than CF standard-4 at full CPU ($0.40/h), with 2x the vCPU and ~2.7x the RAM. Spot instances can be evicted, but a failed Nix build simply reruns, so builds tolerate interruption.
- At 5–100 h/month: m8g.2xlarge on-demand costs $2.15–43, plus ~$19 for a persistent 200 GB gp3 volume that is billed even while the instance is stopped. Spot drops compute to ~$0.30–19.
- All three are full KVM/Nitro VMs. NixOS images exist, and the Nix sandbox (user namespaces), sshd and arbitrary disk sizes work as on any VM. Using one as an SSH remote builder is standard. Cold start of a stopped VM (boot plus sshd) is typically tens of seconds, but I found no Oct-2026 source for that figure.
- Since the machine stops between bursts, an on-demand wake-up hook is needed (for example, start the instance before `nix build` and let an idle timer shut it down).

### Gaps
- No official AWS Frankfurt per-GB internet egress price was found; the AWS page did not render it. It is widely $0.09/GB, but that is unverified here.
- Azure egress and VM billing granularity were not fetched.
- GCP billing granularity, official Hyperdisk/pd-balanced prices and c4/c4d/t2d EU prices were not retrieved. c4a only.
- The AWS spot.js feed has no date and omits 8th-gen types, so AWS spot for m8g/c8g in the EU is unverified.
- No measured cold-start times for 2026.

## Oracle Cloud Always Free Ampere A1

### Takeaway
The Always Free A1 allowance was cut in June 2026 from 4 OCPU / 24 GB to **2 OCPU / 12 GB**. Capacity remains scarce, and idle instances can be reclaimed. As a free aarch64 builder it still works (a full VM with 200 GB of free block storage), but it is small and unreliable.

### Cited Findings
- Oracle docs now say: "All tenancies get the first 1,500 OCPU hours and 9,000 GB hours per month for free for VM instances using the VM.Standard.A1.Flex shape … For Always Free tenancies, this is equivalent to 2 OCPUs and 12 GB of memory." — [Oracle Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm)
- 200 GB of Block Volume (boot plus block combined) and five volume backups are free; the volume must be in the home region. 10 TB/month of outbound data is free. — [Oracle Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm)
- Idle reclamation: an instance is "idle if, during a 7-day period … CPU utilization for the 95th percentile is less than 20%, Network utilization is less than 20%, Memory utilization is less than 20% (applies to A1 shapes only)". — [Oracle Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm)
- InfoQ (2026-07-03) reports the details of the cut:
  - It took effect 2026-06-15 with no announcement. Quotas went from 3,000 OCPU-h / 18,000 GB-h to 1,500 / 9,000.
  - Free-only accounts had over-limit instances shut down until resized.
  - Users report that Oracle support said Pay-As-You-Go accounts may still use 4 OCPU / 24 GB at no charge. Oracle has not confirmed this publicly, and the docs do not distinguish account types.
  - Fine print says a terminated grandfathered resource may not be recreatable above the new limit.
  - [InfoQ](https://infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)
- Popular regions can show "out of capacity" errors for weeks, and users rely on retry scripts. This comes from a third-party blog. — [braindetox](https://braindetox.kr/en/posts/oracle_always_free_tier_reduced_2026.html), [space-node](https://space-node.net/blog/oracle-cloud-free-vps-guide-2026)

### Inferences
- 2 OCPU on A1 equals 2 Ampere cores (no SMT), which is weak for large aarch64 builds. It is still useful as a free, always-on aarch64 remote builder for small derivations, or as a fallback.
- An intermittently used builder will fail all three idle criteria and risk reclamation. Users typically run load generators to avoid this, which is against the spirit of the terms.
- A PAYG upgrade may restore 4/24 free, but that rests only on support emails and is unconfirmed.

### Gaps
- No official Oracle statement on whether PAYG tenancies keep 4/24.
- No current data on capacity availability in EU regions (Frankfurt, Amsterdam, Zurich).

## Fly.io Machines

### Takeaway
performance-8x with 32 GB costs $0.50/h in iad and ~$0.58/h in fra. Billing is per second while running. A stopped Machine costs only $0.15/GB-month for rootfs, and volumes cost $0.15/GB-month. Each Machine is a Firecracker microVM with its own kernel, so a Nix sandbox is likely possible. The ~8 GB rootfs means /nix must live on a volume.

### Cited Findings
- Performance Machines (iad, markup 1.0): $0.000012732 per vCPU-second (= $0.0458/vCPU-h calc), with 2 GB RAM per vCPU included. Extra RAM costs ~$0.000002316/GB-s (~$6/GB-month). — [Fly.io pricing](https://docs.fly.io/about/pricing)
  - performance-4x/8GB $0.1833/h; 4x/16GB $0.25/h; 4x/32GB $0.3834/h
  - performance-8x/16GB $0.3667/h; **8x/32GB $0.5001/h**; 8x/64GB $0.7669/h
- Frankfurt (fra) has a 1.153846 markup, so performance-8x/32GB in fra ≈ $0.577/h (calc). — [Fly.io pricing](https://docs.fly.io/about/pricing)
- Billing is by the second while running. Stopped Machines bill only rootfs at $0.15/GB-month. Volumes cost $0.15/GB-month of provisioned capacity, even when detached or attached to a stopped Machine. Snapshots cost $0.08/GB-month (first 10 GB free), charged since 2026-01-01. — [Fly.io pricing](https://docs.fly.io/about/pricing)
- Europe internet egress is $0.02/GB. Reservations give 40% off CPU and extra RAM (e.g. $144/yr for $20/month of credit). — [Fly.io pricing](https://docs.fly.io/about/pricing)
- Fly Machines are KVM hardware-isolated VMs that start in "a few hundred milliseconds". — [Fly.io ai.md / docs](https://fly.io/ai.md)
- The image size limit is ~8 GB uncompressed. Users report the rootfs is limited to ~8 GB, is "not really meant for writing", and is throttled to ~8 MB/s. These are community reports, not official docs. — [Fly community: image limit](https://community.fly.io/t/docker-image-size-limit-raised-from-2gb-to-8gb/14749), [Fly community: extend root volume](https://community.fly.io/t/is-it-possible-to-extend-the-root-volume-beyond-8gb/21055)

### Inferences
- A 200 GB volume for /nix costs $30/month (calc), about 1.5x EBS gp3. The volume is pinned to one host, so the Machine may fail to start if that host lacks capacity.
- Because each Machine is a microVM with its own kernel and runs as root inside the guest, nix-daemon with `sandbox = true` and sshd should work. This is not confirmed by a 2026 source; test it.
- For bursty use, Fly is the closest "serverless VM" option: start on demand, stop when idle, and pay only for the volume while stopped.

### Gaps
- No source confirms that the Nix sandbox works on Fly Machines or documents a Fly-based Nix remote builder.
- No official max RAM for performance Machines (the presets go to 64 GB on 8x; larger presets were not checked) and no official volume size cap.

## Modal, Railway, Northflank and similar serverless containers

### Takeaway
These platforms price 8/32 at $0.40–0.67/h. They target app containers, not privileged build hosts. Modal runs on gVisor and Railway blocks custom seccomp/security options, so the Nix sandbox is unlikely to work on either. Northflank is the most plausible of the three, because it offers microVM isolation and BYOC. None is a natural fit for a long-lived SSH Nix remote builder.

### Cited Findings
- **Modal** — [Modal pricing](https://modal.com/pricing)
  - Prices: $0.0000131 per physical core-second (1 core = 2 vCPU) and $0.00000222/GiB-s. Sandboxes cost $0.00003942/core-s and $0.00000667/GiB-s.
  - Multipliers: region selection 1.15–1.75x; non-preemptible 3x.
  - Starter plan includes $30/month of credits and 1 TiB/month of free egress. Volumes cost $0.09/GiB-month (1 TiB free). Egress costs $0.04/GiB.
  - 8 vCPU/32 GiB base ≈ 4 x $0.04716 + 32 x $0.00799 = **$0.444/h** (calc), before region and non-preemptible multipliers.
- Modal Sandboxes run on gVisor. — [Northflank blog (third-party)](https://northflank.com/blog/daytona-vs-modal)
- **Railway** — [Railway pricing](https://docs.railway.com/reference/pricing/plans)
  - Containers cost $20/vCPU-month and $10/GB-month. 8/32 ≈ **$0.67/h** (calc).
  - Volumes cost $0.15/GB-month and egress $0.05/GB.
  - Hobby plan maximums: 48 vCPU / 48 GB per service, volume 5 GB. Pro plan: volume up to 1 TB.
  - Railway also has "VM pricing" for sandboxes: $50/vCPU-month and $50/GB-month, per second.
- A Railway responder said the platform does not expose custom security_opt/seccomp for normal services, which blocks the namespace calls that Chromium's sandbox needs. This is a community thread, not an official statement. — [Railway Station thread](https://station.railway.com/questions/staging-service-needs-a-container-securi-d3d3154a)
- **Northflank** — [Northflank pricing](https://northflank.com/pricing)
  - Prices: $0.01667/vCPU-h and $0.00833/GB-h. nf-compute-800-32 (8 dedicated vCPU / 32 GB) costs **$0.40/h** ($288/month).
  - Disk costs $0.15/GB-month and egress $0.06/GB. Billing is per second.
  - BYOC on AWS/GCP/Azure is offered "No added cost" on pay-as-you-go.
- Northflank sandboxes use Kata Containers, Firecracker or gVisor, depending on workload. — [Northflank blog](https://northflank.com/blog/modal-vs-railway-sandboxes)
- In general, Nix `sandbox = true` requires Linux user namespaces. On Kubernetes-hosted runners it only worked after raising the host user-namespace limit. — [NixOS Discourse](https://discourse.nixos.org/t/sandbox-true-requires-linux-user-namespaces-what-gives/77519)

### Inferences
- Without user namespaces, Nix can still build with `sandbox = false`, but that loses purity guarantees. Builds may then pass on the platform and fail elsewhere, or the reverse.
- These platforms expose HTTP services, not raw TCP/SSH, by default. Using one as an `ssh-ng://` remote builder would need TCP proxying or a tunnel (e.g. Tailscale). This is not verified per platform.
- None of them beats a hyperscaler spot VM on price for 8/32.

### Gaps
- Render and Koyeb were not researched; no pricing or privilege data.
- No official docs found on user-namespace support for Modal, Railway or Northflank. A test build with `sandbox = true` is needed.

## Cloudflare Containers (verification)

### Takeaway
Pricing is unchanged, and **standard-4 (4 vCPU / 12 GiB / 20 GB) is still the maximum**, including for custom instance types. Disk is ephemeral and capped at 20 GB, which is too small for a persistent /nix/store of 100–200 GB. Each instance is a Firecracker microVM with its own kernel. Docker-in-Docker and SSH via Wrangler arrived in 2026. User namespaces are not documented.

### Cited Findings
- Instance types top out at standard-4: 4 vCPU, 12 GiB, 20 GB. — [CF Containers pricing](https://developers.cloudflare.com/containers/pricing/)
- Unit prices: $0.000020/vCPU-s, $0.0000025/GiB-s, $0.00000007/GB-s. — [CF Containers pricing](https://developers.cloudflare.com/containers/pricing/)
- Workers Paid includes 375 vCPU-min, 25 GiB-h and 200 GB-h. Egress in NA/EU costs $0.025/GB, with 1 TB/month included. — [CF Containers pricing](https://developers.cloudflare.com/containers/pricing/)
- Custom instance limits: max 4 vCPU, 12 GiB and 20 GB disk, with at least 3 GiB per vCPU. — [CF Containers limits](https://developers.cloudflare.com/containers/platform-details/limits/)
- Account limits: 6 TiB memory, 1,500 vCPU and 30 TB disk concurrent; 50 GB total image storage. Snapshots max out at 20 GB and are kept 30 days. Instance maximums "can be increased through your account team, a support ticket, or a limit increase request form". — [CF Containers limits](https://developers.cloudflare.com/containers/platform-details/limits/)
- "Each container instance runs in a Firecracker microVM with its own kernel and network." — [CF Containers architecture](https://developers.cloudflare.com/containers/platform-details/architecture/)
- Lifecycle — [CF Containers architecture](https://developers.cloudflare.com/containers/platform-details/architecture/)
  - Cold starts are "often … in the 1-3 second range".
  - The default `sleepAfter` is 10 minutes.
  - Stopping sends SIGTERM, waits up to 15 minutes, then sends SIGKILL.
  - No maximum run time is documented.
  - Disk is ephemeral; a restarted instance starts fresh unless snapshots or FUSE are used.
- 2026 changelog — [CF Containers changelog](https://developers.cloudflare.com/changelog/product/containers/)
  - Custom instance types became available to all users (2026-01-05).
  - Docker-in-Docker support (2026-02-17).
  - Concurrent limits rose 15x (2026-02-25).
  - SSH into instances via Wrangler (2026-03-12), enabled by default (2026-05-12), with Wrangler usable as an SSH ProxyCommand (2026-05-28). No public ports are exposed.
  - GA (2026-04-13).
  - `exec()` added (2026-06-18).
  - The disk-to-memory ratio limit was removed (2026-09-29).
  - Full-filesystem snapshot APIs entered public beta (2026-09-30).
  - Active-CPU pricing ("only pay for used CPU cycles") dates from 2025-11-21.
  - No entry mentions user namespaces or privileged mode.

### Inferences
- A remote builder could connect through `ProxyCommand wrangler containers ssh …`-style access, since the ProxyCommand support exists. But each new connection to a sleeping instance first triggers a cold start, and the /nix/store is lost on stop unless it is snapshotted (20 GB max).
- Docker-in-Docker support suggests the microVM grants enough privilege for namespaces/cgroups, so the Nix sandbox may well work. This is unconfirmed and needs a test.
- With Active-CPU pricing, a standard-4 that sits waiting on downloads is cheaper than $0.40/h. Even so, per useful vCPU it is pricier than hyperscaler spot by ~5–10x, and the 12 GiB / 20 GB caps rule out large builds (e.g. LLVM, Chromium or kernel builds with deep closures).
- The free allowance (375 vCPU-min) covers only ~1.5 h of standard-4 at full CPU per month (calc).

### Gaps
- No documentation or report of Nix (or `unshare --user`) running inside Cloudflare Containers.
- No documented maximum run time or CPU throttling policy beyond the instance size.
- Whether Cloudflare would raise per-instance maximums (above 4 vCPU / 20 GB) on request for a small account is unknown.
