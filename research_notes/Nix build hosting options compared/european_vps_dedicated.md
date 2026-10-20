# European VPS and dedicated servers as Nix remote builders (October 2026)

Research date: 2026-10-12. Prices are in EUR excluding VAT unless noted. "Per vCPU-h" means the hourly price divided by the vCPU count. Baseline for comparison: Cloudflare Containers standard-4, about $0.40/h for 4 vCPU, so about **$0.10 per vCPU-h**, plus $5/mo.

Note on specs: Hetzner Cloud vCPU/RAM/disk sizes below come from prior knowledge of the product line (CX23 2/4/40, CX33 4/8/80, CX43 8/16/160, CX53 16/32/320; CAX11 2/4/40 … CAX41 16/32/320; CPX22 2/4/80, CPX32 4/8/160, CPX42 8/16/320, CPX52 12/24/480, CPX62 16/32/640; CCX13 2/8/80, CCX23 4/16/160, CCX33 8/32/240, CCX43 16/64/360, CCX53 32/128/600, CCX63 48/192/960, as vCPU/GB RAM/GB disk). I did not re-verify them against a 2026 page, because hetzner.com/cloud no longer shows the specs in fetchable text. The prices are verified.

## Hetzner Cloud (CX, CPX, CCX, CAX) after 15 June 2026: prices, billing, power-off

### Takeaway
On 15 June 2026 the dedicated-vCPU CCX line went up 2.1–2.7x and the shared AMD CPX line about 2.4–2.8x. Cost-optimized CX (Intel/AMD shared) and CAX (ARM shared) rose only about 31–37%. CX and CAX remain by far the cheapest per vCPU-h (€0.003–0.005), but since about September 2026 they are reportedly "Currently not available" to order. Billing is hourly with a monthly cap. A powered-off server is still billed. Only deleting it stops billing, which suits snapshot → create → build → delete workflows.

### Cited Findings
- The adjustment took effect 15 June 2026, 08:00 CEST. It applies to new orders and rescales. Existing servers keep their old prices. — [Hetzner Docs price adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/); [heise](https://heise.de/-11333037)
- Germany/Finland prices (old → new, hourly / monthly cap) and derived per vCPU-h at the new price — [Hetzner Docs price adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/):

| Plan | vCPU type | vCPU/RAM/disk* | Old €/h / €/mo | **New €/h** | **New €/mo cap** | New €/vCPU-h |
|---|---|---|---|---|---|---|
| CX23 | shared x86 | 2/4/40 | 0.0064 / 3.99 | 0.0088 | 5.49 | 0.0044 |
| CX33 | shared x86 | 4/8/80 | 0.0104 / 6.49 | 0.0136 | 8.49 | 0.0034 |
| CX43 | shared x86 | 8/16/160 | 0.0192 / 11.99 | 0.0256 | 15.99 | 0.0032 |
| CX53 | shared x86 | 16/32/320 | 0.0360 / 22.49 | 0.0473 | 29.49 | 0.0030 |
| CAX11 | shared ARM64 (Ampere) | 2/4/40 | 0.0072 / 4.49 | 0.0096 | 5.99 | 0.0048 |
| CAX21 | shared ARM64 | 4/8/80 | 0.0128 / 7.99 | 0.0168 | 10.49 | 0.0042 |
| CAX31 | shared ARM64 | 8/16/160 | 0.0256 / 15.99 | 0.0336 | 20.99 | 0.0042 |
| CAX41 | shared ARM64 | 16/32/320 | 0.0505 / 31.49 | 0.0657 | 40.99 | 0.0041 |
| CPX22 | shared AMD | 2/4/80 | 0.0128 / 7.99 | 0.0312 | 19.49 | 0.0156 |
| CPX32 | shared AMD | 4/8/160 | 0.0224 / 13.99 | 0.0569 | 35.49 | 0.0142 |
| CPX42 | shared AMD | 8/16/320 | 0.0408 / 25.49 | 0.1114 | 69.49 | 0.0139 |
| CPX52 | shared AMD | 12/24/480 | 0.0585 / 36.49 | 0.1610 | 100.49 | 0.0134 |
| CPX62 | shared AMD | 16/32/640 | 0.0809 / 50.49 | 0.2083 | 129.99 | 0.0130 |
| CCX13 | dedicated AMD | 2/8/80 | 0.0256 / 15.99 | 0.0689 | 42.99 | 0.0345 |
| CCX23 | dedicated AMD | 4/16/160 | 0.0505 / 31.49 | 0.1378 | 85.99 | 0.0345 |
| CCX33 | dedicated AMD | 8/32/240 | 0.1001 / 62.49 | 0.2219 | 138.49 | 0.0277 |
| CCX43 | dedicated AMD | 16/64/360 | 0.2003 / 124.99 | 0.4423 | 275.99 | 0.0276 |
| CCX53 | dedicated AMD | 32/128/600 | 0.4006 / 249.99 | 0.8550 | 533.49 | 0.0267 |
| CCX63 | dedicated AMD | 48/192/960 | 0.6001 / 374.49 | 1.3678 | 853.49 | 0.0285 |

  *Specs from prior knowledge; see note at top.
- WZ-IT gives the same per-plan changes, for example CPX52 +175.3%, CCX13 +168.9%, CX23 +37.6%, CAX11 +33.4%. — [WZ-IT, 15.06.2026, updated 01.10.2026](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/)
- An earlier 2026 round on **1 April 2026** raised prices by up to 37% and also hit existing customers. I found no per-plan figures for that round. — [WZ-IT](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/); [Findstack](https://findstack.com/resources/hetzner-price-increase-2026); [agentdeals (published 2026-03-25)](https://agentdeals.dev/hetzner-pricing-2026)
- **Availability:** WZ-IT says the cost-optimized line (CX/CAX) has shown "Currently not available" on Hetzner's cloud page since early September 2026, still as of 1 October 2026. A capacity status notice open since 26 June 2026 limits cloud provisioning for all new customers and some existing ones. — [WZ-IT](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/). This is secondary and I could not confirm it from hetzner.com.
- **Billing:** a server is billed for as long as it exists, "regardless of whether it is turned on or not". Billing stops only when the server is deleted. Usage is billed per started hour, rounded up, and capped at the monthly price. — [Hetzner Cloud billing FAQ](https://docs.hetzner.com/cloud/billing/faq/)
- **IPv4:** Primary IPs have a fixed price and are billed separately. Primary IPv6 is free. — [Hetzner Cloud billing FAQ](https://docs.hetzner.com/cloud/billing/faq/). The page does not state the IPv4 price.

### Inferences
- At 5–100 builder-hours per month, hourly use costs far less than the monthly cap. Examples at 100 h: CX43 (8 vCPU) €2.56, CAX41 (16 ARM vCPU) €6.57, CPX42 (8 vCPU) €11.14, CCX33 (8 dedicated) €22.19. That is €0.003–0.03 per vCPU-h, versus about $0.10 for Cloudflare standard-4. Hetzner is 3–30x cheaper per vCPU-h.
- On-demand pattern: keep a snapshot (or provision from a NixOS image with nixos-infect/nixos-anywhere), create the server, build, push to R2, then delete it. Rounding up per hour penalises many short bursts. A builder that stays up for a session and is deleted when idle fits better.
- A persistent /nix/store means keeping the server, which means paying the monthly cap. Alternatively, rely on R2 as the substituter so a fresh builder fetches dependencies instead of rebuilding them.
- All Hetzner Cloud servers are full KVM VMs, so the Nix sandbox (user namespaces) works. CAX gives native aarch64-linux builds; at the old price it was the standard cheap ARM option.
- The CX/CAX availability problem is the biggest practical risk. If new CX/CAX servers cannot be created, the cheapest available Hetzner option becomes CPX (about €0.013–0.016/vCPU-h).

### Gaps
- IPv4 Primary IP price in 2026. Prior knowledge says €0.50/mo (about €0.0008/h), but I did not verify it for 2026.
- Whether CX/CAX are orderable today (October 2026). This needs a live console check.
- Snapshot storage price in 2026 (affects the cost of keeping a builder image).

## Hetzner dedicated (AX, EX) and Server Auction

### Takeaway
After June 2026 the official prices are AX42-1 €97.30/mo plus €49 setup, and EX63-1 €147.30/mo plus €74 setup. "Limited" variants are cheaper: AX41-1-LTD €57.30 with no setup fee, AX42-1-LTD €77.30 plus €39 setup. The reported "AX42 ≈ €187/mo" does **not** match Hetzner's official price page. Dedicated servers are billed monthly with a setup fee, so they suit only a permanently running builder. The Server Auction has no setup fee, but I could not get current live prices.

### Cited Findings
- New monthly prices and setup fees (Falkenstein/Helsinki, excl. VAT, **excl. IPv4**) — [Hetzner Docs price adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/):
  - AX42-1 €97.30 + €49 setup; AX102-1 €257.30 + €129; AX162-1 €612.30 + €304
  - EX63-1 €147.30 + €74; EX131-1 €557.30 + €279
  - Limited (while supply lasts): AX41-1-LTD €57.30 + €0; AX42-1-LTD €77.30 + €39; AX102-1-LTD €157.30 + €39; AX162-1-LTD €317.30 + €39; EX44-1-LTD €57.30 + €0; EX63-1-LTD €97.30 + €39; EX131-1-LTD €267.30 + €39
- AX CPU options on the matrix page are Ryzen 5 3600 (AX41), Ryzen 7 PRO 8700GE (8C, AX42), Ryzen 9 7950X3D (16C, AX102), and EPYC 9454P (48C, AX162). RAM is 64 GB DDR4/DDR5 ECC upward. NVMe options include 2x512 GB (AX41/AX42 class). Prices did not render on the page. — [Hetzner AX matrix](https://www.hetzner.com/dedicated-rootserver/matrix-ax/)
- WZ-IT says the June round lowers the one-time setup fees for most dedicated servers and folds that cost into higher monthly rates. It also says Server Auction (used hardware) is exempt from the adjustment. — [WZ-IT](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/)
- Auction prices from secondary, competitor-authored sources: an entry-level Ryzen 5 with 64 GB at about €40–55/mo, and a Ryzen 7 with 64–128 GB at about €55–90/mo. Auction servers have no setup fee. Inventory changes daily. — [valebyte](https://valebyte.com/en/blog/hetzner-cloud-vs-hetzner-auction-vs-hetzner-dedicated-which-to-choose/). The date is unclear and I treat these numbers as low confidence.

### Inferences
- **"AX42 ≈ €187/mo" conflicts with the official page (€97.30).** Possible explanations: a non-DE/FI location, an added-options configuration, a different currency/VAT, or a misreport. Use €97.30 + €49 setup unless the order page shows otherwise.
- A dedicated AX42 (8C/16T, 64 GB) running permanently costs €97.30/mo, which is €0.133/h over 730 h. At 100 builder-h/mo the effective price is about €0.97 per builder-hour. It beats hourly cloud only when the builder runs well over about 440 h/mo compared with CCX33-class hourly use. It does give a persistent, large /nix/store and no cold starts.
- Auction boxes (if €40–55 for 64 GB Ryzen still holds) are the cheapest always-on option. They have no setup fee and can be cancelled monthly (prior knowledge, not re-verified).

### Gaps
- Live Server Auction prices: I could not fetch the JSON feed (`live_data_sb_EUR.json` returned HTML).
- The 29 April 2026 setup-fee change mentioned in the brief: I found no primary source describing it.
- The current IPv4 surcharge for dedicated servers. The price table explicitly excludes IPv4.

## OVHcloud (VPS, Public Cloud hourly, Eco/Kimsufi/So You Start)

### Takeaway
OVHcloud raised prices in 2026. Public Cloud and Bare Metal rose about 9–11% for new deployments from about April. VPS rose about 44–67%. The Game/dedicated ranges rose up to 87% from about September/October. Public Cloud b3/c3 instances bill hourly at about €0.023–0.026 per vCPU-h, which is close to Hetzner CCX and Scaleway POP2-HC. Eco/Kimsufi is monthly only, and its low end is mostly old Intel.

### Cited Findings
- OVHcloud limited the average increase for Public Cloud, Private Cloud, and Bare Metal deployed in 2026–2028 to 9–11%, plus 2–6% for services deployed before 2025. It cites RAM and storage costs. — [OVHcloud repricing page](https://us.ovhcloud.com/lp/new-services-repricing/); [OVHcloud blog](https://us.ovhcloud.com/resources/blog/cloud-infrastructure-pricing-in-2026/)
- VPS: VPS-1 went from €4.49 to €6.49/mo (+44–48% for the range) — [Capital & Compute](https://capitalandcompute.net/blog/ovhcloud-price-increase-2026/). A conflicting USD figure: VPS-1 $4.90 → $7.60, VPS-4 $26.00 → $43.50 — [agentdeals](https://agentdeals.dev/vendor/ovhcloud). The sources do not reconcile.
- Dedicated: increases began September 2026, with the Game range up to +87% — [TechRadar](https://techradar.com/pro/ovh-cloud-tells-users-to-expect-87-percent-price-rise-with-gaming-servers-hit-particularly-hard); renewals from 1 October 2026 — [Capital & Compute](https://capitalandcompute.net/blog/ovhcloud-price-increase-2026/)
- According to Itdaily, OVHcloud did not raise the hourly compute rate for all-inclusive Public Cloud instances. It split the bill into components instead. — [Itdaily](https://itdaily.com/news/cloud/ovhcloud-price-increase-ram/). This partly conflicts with the official 9–11% figure.
- Public Cloud hourly: b3-8 (2 vCPU, 8 GB) about €0.0512/h; c3-8 (4 vCPU, 8 GB) about €0.0913/h on the Ireland page via [vpsbenchmarks b3-8](https://www.vpsbenchmarks.com/hosters/ovhcloud/plans/1419) and [vpsbenchmarks c3-8](https://www.vpsbenchmarks.com/hosters/ovhcloud/plans/1471). The US list shows $0.0566 and $0.0907, effective 1 March 2026 ([OVHcloud prices](https://www.ovhcloud.com/en/public-cloud/prices)). Cloud-Mercato shows c3-8 at €0.083 in GRA/DE/SBG ([Cloud-Mercato](https://pcr.cloud-mercato.com/providers/ovh/flavors/C3-8)). I could not read the official EUR page (truncated).
  - Derived: b3-8 ≈ €0.026/vCPU-h; c3-8 ≈ €0.021–0.023/vCPU-h.
- Eco range: Kimsufi from $11.10/mo, 4–24 cores, up to 256 GB RAM — [OVHcloud Eco compare](https://eco.ovhcloud.com/en/compare/). Ryzen appears in Rise (for example RISE-M, Ryzen 9 9900X, 64 GB, 2x512 GB NVMe, $118/mo, "coming soon" on the US page). Kimsufi entry hardware is mostly older Intel. — [klymentiev, June 2026](https://klymentiev.com/blog/cheap-dedicated-server-2026); [valebyte](https://www.valebyte.com/es/blog/ovh-soyoustart-vs-kimsufi-vs-eco-where-the-budget-dedicated-servers-moved/)

### Inferences
- OVH Public Cloud instances are full KVM VMs, so the Nix sandbox works, and billing is hourly. Prior knowledge (not re-verified): OVH bills a stopped Public Cloud instance; only "shelving" or deleting stops compute billing. Treat as unverified.
- OVH VPS and Eco are monthly products, so they fit only an always-on builder.

### Gaps
- Exact EUR Public Cloud prices for October 2026 (official page truncated), stopped-instance billing, and the IPv4 policy (prior knowledge: a public IPv4 is included with Public Cloud instances).
- Current EUR prices for the VPS range and Eco Ryzen models.

## Netcup (root servers, VPS, ARM)

### Takeaway
Netcup raised prices in 2026: +24.33% for new orders from 19 March, and +18.51% for existing contracts from 1 May. Root servers (dedicated EPYC 9645 cores) and ARM64 vServers (Ampere Altra Max) are very cheap per core, but the billing is monthly. The 1-month term costs more; the 12/24-month terms are discounted 13%/26%. There is no hourly billing, so Netcup fits only an always-on builder. It is the cheapest always-on ARM64 option found: 16 ARM cores, 64 GB, 1 TB for about €67/mo.

### Cited Findings
- Netcup price increase: new orders +24.33% from 19 March 2026; existing contracts +18.51% from the next billing period on or after 1 May 2026; storage add-ons +21.52%. Reason given: memory costs. — [deskmodder](https://www.deskmodder.de/blog/?p=210508); [LowEndTalk](https://lowendtalk.com/discussion/comment/4750887/). These are secondary reports of netcup's announcement.
- Root Server G12.5 (AMD EPYC 9645, dedicated cores, NVMe), 12-month-term price, incl. 19% VAT / derived excl. VAT — [netcup root server](https://www.netcup.com/en/server/root-server):
  - RS 1000: 4 cores, 8 GB, 128 GB — €25.00 incl. / about €21.01 excl.
  - RS 2000: 8 cores, 16 GB, 256 GB — €46.81 / about €39.34
  - RS 4000: 12 cores, 32 GB, 512 GB — €89.50 / about €75.21
  - RS 8000: 16 cores, 64 GB, 1 TB — €170.69 / about €143.44
  - The page also shows a second, unlabelled figure (for example RS 2000 €40.70) that does not equal the incl-VAT figure ÷ 1.19. It could be another term's price. Unresolved.
  - Terms are 1, 12 or 24 months (−13% and −26% for the longer ones). Hourly billing is not mentioned.
- ARM64 vServer G12.5 (Ampere Altra Max), 12-month term, excl. VAT — [netcup ARM](https://www.netcup.com/en/server/arm-server): VPS 1000 ARM 4c/8 GB/128 GB €14.50; VPS 2000 ARM 8c/16 GB/256 GB €26.92; VPS 4000 ARM 12c/32 GB/512 GB €45.36; VPS 8000 ARM 16c/64 GB/1 TB €67.11. Whether the cores are dedicated or shared is not stated.

### Inferences
- Running permanently, the RS 2000 (8 dedicated cores) costs about €0.0067 per core-hour over 730 h; the VPS 8000 ARM costs about €0.0057 per core-hour. Both cost more than hourly Hetzner CX/CAX at under about 100 h/mo, but they come with a persistent store and large disks.
- Netcup servers are KVM, so the Nix sandbox works (prior knowledge; NixOS installs via custom ISO or nixos-anywhere).

### Gaps
- Setup fees for 1-month terms: netcup often charges them on short terms or runs promotions without them ([mydealz](https://www.mydealz.de/deals/netcup-vps-1000-und-vps-2000-ohne-mindestlaufzeit-und-einrichtungsgebuhr-2734113)). Current terms not confirmed.

## Scaleway (Instances hourly, ARM, Elastic Metal)

### Takeaway
Scaleway bills Instances by the hour (minimum 60 minutes per start/stop cycle). A **powered-off instance is not billed for compute**, unlike Hetzner, but block storage and flexible IPv4 (€0.004/h) continue. Per vCPU-h: POP2-HC (dedicated cores) €0.0266, COPARM1 ARM about €0.021, DEV1 shared about €0.011. That is around Hetzner CCX level, about 2–8x the cost of Hetzner CX/CAX. Elastic Metal is billed even when powered off.

### Cited Findings
- PAR-1 prices before tax — [Scaleway Instances pricing](https://www.scaleway.com/en/pricing/virtual-instances/):
  - DEV1-L 4 vCPU/8 GB €0.04284/h (~€31.27/mo) → €0.0107/vCPU-h; DEV1-XL 4/12 GB €0.06508/h
  - PLAY2-MICRO 4/8 GB €0.05508/h
  - PRO2-XS 4/16 GB €0.1122/h (€0.028/vCPU-h); PRO2-S 8/32 GB €0.22338/h
  - POP2-4C-16G €0.147/h; POP2-8C-32G €0.29/h
  - POP2-HC ("dedicated physical cores"): 4C-8G €0.1064/h (€77.67/mo); 8C-16G €0.2128/h (€155.34/mo); 16C-32G €0.4256/h → €0.0266/vCPU-h at every size
  - The "approx. per month" figures are hourly × 730, not a stated cap. Storage and IPv4 are excluded from the list prices.
- COPARM1 (ARM64) runs from €0.0426/h for 2C-8G to €0.6935/h for 32C-128G (about €0.021–0.022/vCPU-h). Flexible IPv4 costs €0.004/h. — [Scaleway Instances FAQ (via search)](https://scaleway.com/en/docs/faq/instances); also [Holori, Dec 2025](https://calculator.holori.com/scaleway/vm/COPARM1-32C-128G). COPARM1 was not on the current pricing page I fetched, so it may be discontinued or only listed elsewhere. Not confirmed for October 2026.
- Billing: a powered-off Instance is not billed for compute. Each resource is billed for a minimum of 60 minutes, and each uninterrupted start–stop period counts as a separate resource. Flexible IPs are billed from reservation until cancelled. Elastic Metal is still billed when powered off. — [Scaleway billing FAQ](https://www.scaleway.com/en/docs/billing/faq/)
- LowEndBox lists Scaleway among the providers that raised prices between April and June 2026. — [LowEndBox via search](https://lowendbox.com/?p=52845). I found no details.

### Inferences
- Scaleway's power-off-without-compute-billing model is the closest European fit for a "stop the builder, keep its /nix/store" workflow. You pay only for the block volume while it is off. With Hetzner you must delete the server and keep a snapshot.
- POP2-HC-4C-8G (€0.1064/h) is the nearest match to Cloudflare standard-4 (about $0.40/h): about a quarter of the price, with dedicated cores and a full VM.

### Gaps
- Details of Scaleway's 2026 price change; Elastic Metal prices; the block storage price per GB-month; and whether COPARM1 still exists.

## Contabo (VPS/VDS)

### Takeaway
Contabo sells very cheap but monthly-only VPS (no hourly billing). Its 2026 prices moved in both directions: up about 7–22% on small plans in June, then down 5–17% in August/September. The plan line-up was renamed to Cloud VPS 4–18. Cheap shared vCPUs and the monthly term make it a poor fit for bursty builds. It can work as a slow always-on builder with a large disk.

### Cited Findings
- Current line-up: Cloud VPS 4 (4 vCPU/8 GB/100 GB SSD), 6 (6/12/200 SSD or 100 NVMe), 8 (8/24/300 or 150), 12 (12/48/400 or 200), 16 (16/64/500 or 250), 18 (18/96/600 or 300). Prices are quoted incl. VAT as a 24-month effective rate, from €4.40/mo. The extracted figures were garbled. Display values: €5.50 / 7.50 / 14.00 / 25.00 / 37.00 / 49.00. Hourly billing is not mentioned. — [Contabo VPS](https://contabo.com/en/vps/)
- 2026 changes (third-party tracker): mid-June increases of up to 22% (Cloud VPS 10 €3.60 → €4.40, Cloud VPS 20 +7% to €6.00), a dedicated-server hike in week 29, cuts of 5–11% in week 31, and cuts of about 17% to Cloud VPS 18/Performance VPS in week 38. — [PricingSaaS Q2](https://pricingsaas.com/companies/contabo.main/diffs/2026Q2); [PricingSaaS W38](https://pricingsaas.com/companies/contabo.main/diffs/2026W38)

### Inferences
- Contabo VPS are KVM, so the Nix sandbox works. Their vCPUs are heavily shared (based on prior benchmark knowledge), so build times are unpredictable.

### Gaps
- Exact excl-VAT monthly prices, setup fees for short terms (Contabo historically charged setup fees on 1-month terms), and VDS prices.

## Hourly billing vs monthly-only, and cheap ARM64 (summary)

### Takeaway
Only Hetzner Cloud, Scaleway Instances, and OVH Public Cloud offer hourly billing suited to on-demand builders. Hetzner bills while powered off, so you must delete the server. Scaleway stops compute billing when powered off. Netcup, Contabo, OVH VPS/Eco, and Hetzner dedicated/auction are monthly-only. For ARM64: Hetzner CAX (hourly, €0.004/vCPU-h, availability uncertain), Netcup VPS ARM (monthly, €67/mo for 16c/64 GB), and Scaleway COPARM1 (hourly, about €0.021/vCPU-h, existence in 2026 unconfirmed).

### Cited Findings
- Hetzner Cloud bills hourly with a monthly cap and charges for a server while it exists, even powered off — [Hetzner billing FAQ](https://docs.hetzner.com/cloud/billing/faq/)
- Scaleway bills hourly, does not bill compute while powered off, and has a 60-minute minimum per cycle — [Scaleway billing FAQ](https://www.scaleway.com/en/docs/billing/faq/)
- Netcup terms are 1/12/24 months — [netcup](https://www.netcup.com/en/server/root-server); Contabo's initial term is 1 month or longer — [Contabo](https://contabo.com/en/vps/)
- CAX prices — [Hetzner Docs](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/); Netcup ARM — [netcup ARM](https://www.netcup.com/en/server/arm-server)

### Inferences
Cost at 100 builder-h/mo for an 8-vCPU class machine (excl. IPv4/storage):

| Option | Billing | 8-vCPU price/h | 100 h/mo | Always-on/mo |
|---|---|---|---|---|
| Hetzner CX43 (shared, if orderable) | hourly, billed while off | €0.0256 | €2.56 | €15.99 cap |
| Hetzner CAX31 ARM (shared, if orderable) | hourly | €0.0336 | €3.36 | €20.99 cap |
| Hetzner CPX42 (shared AMD) | hourly | €0.1114 | €11.14 | €69.49 cap |
| Hetzner CCX33 (dedicated) | hourly | €0.2219 | €22.19 | €138.49 cap |
| Scaleway POP2-HC-8C-16G (dedicated) | hourly, not billed when off | €0.2128 | €21.28 | ~€155 |
| OVH c3-16 class (est. 2x c3-8) | hourly | ~€0.18 | ~€18 | n/a |
| Netcup RS 2000 (8 dedicated) | monthly | — | ~€39 | ~€39 |
| Netcup VPS 2000 ARM (8c) | monthly | — | ~€27 | ~€27 |
| Hetzner AX42-1 (8C/16T, 64 GB) | monthly + €49 setup | — | €97.30 | €97.30 |
| Cloudflare standard-4 (4 vCPU) ×2 for 8 vCPU | per use | ~$0.80 | ~$80 + $5 | n/a |

- For 5–100 h/mo, hourly European VMs cost a few euros to about €22/mo for 8 vCPU. Cloudflare Containers costs about 4–30x more per vCPU-h, and it gives only 20 GB ephemeral disk, which is tight for a Nix store.
- OVH c3-16 is an extrapolation, not a quoted price.

### Gaps
- Live verification of Hetzner CX/CAX orderability, the Hetzner IPv4 price, OVH EUR hourly prices, and Server Auction listings in October 2026.
