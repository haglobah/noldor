# CI runners and home server as Nix build hosts (status: October 2026)

Baseline for comparison (from the assignment, not re-verified here): Cloudflare Containers standard-4 = 4 vCPU / 12 GiB / 20 GB disk, ~$0.40/h + $5/mo; Hetzner CCX33 = 8 dedicated vCPU / 32 GB, ~€0.22/h.

Researched on 2026-10-12. Sources were fetched live unless marked otherwise. All hourly figures in "Inferences" are my arithmetic from cited per-minute prices.

## GitHub Actions hosted runners: free minutes, prices, sizes, 2026 changes, Nix tooling

### Takeaway
For public repos, standard runners are free and get 4 vCPU / 16 GB / 14 GB SSD. For private repos, GitHub Free includes 2,000 min/month on 2 vCPU / 8 GB / 14 GB SSD. Larger runners cost $0.012–0.042/min on x64 and are not available to personal accounts. The 14 GB disk is the main Nix constraint. The proposed self-hosted runner fee never took effect.

### Cited Findings
- Free allowance (private repos): GitHub Free 2,000 min/month, 500 MB artifact storage, 10 GB cache per repo. GitHub Pro 3,000 min/month, 1 GB artifacts, 10 GB cache per repo. — [GitHub Docs: Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- "GitHub Actions usage is free for self-hosted runners and for public repositories that use standard GitHub-hosted runners." "Larger runners are always charged for, even when used by public repositories." — [GitHub Docs: Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- Cache overage costs $0.07/GB/month above 10 GB per repo, and only applies if the repo's cache limit is raised above the included amount. — [GitHub Docs: Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- Current per-minute prices on the github.com docs page. Linux x64: 2-core $0.006, 4-core $0.012, 8-core $0.022, 16-core $0.042. Linux arm64: 2-core $0.005, 4-core $0.008, 8-core $0.014, 16-core $0.026. — [GitHub Docs: Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)
- Larger runners are "only available for organizations and enterprises using the GitHub Team or GitHub Enterprise Cloud plans." Jobs are rounded up to whole minutes. — [GitHub Enterprise Server 3.17 docs (via search snippet; the cloud docs are presumed to match but I did not verify)](https://docs.github.com/en/enterprise-server@3.17/billing/reference/actions-runner-pricing)
- Standard runner hardware. Public repos: x64 and arm64 each 4 CPU / 16 GB RAM / 14 GB SSD. Private repos: x64 and arm64 each 2 CPU / 8 GB RAM / 14 GB SSD. `ubuntu-26.04` and `ubuntu-26.04-arm` labels exist. — [GitHub Docs: GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- 2026 pricing changes: GitHub announced in December 2025 a hosted-runner price cut of up to 39% from 1 Jan 2026, plus a $0.002/min platform fee for self-hosted runners in private repos from 1 Mar 2026. It postponed the self-hosted fee within about 48 hours "to re-evaluate our approach." — [Techzine](https://www.techzine.eu/news/devops/137396/github-bends-to-criticism-and-delays-paid-self-hosting-of-runners/); [SAMexpert](https://samexpert.com/github-actions-pricing-backlash-2026/); [IT Brief](https://itbrief.news/story/github-cuts-actions-runner-prices-adds-new-usage-fee)
- A mid-2026 analysis says the self-hosted fee never took effect and has no announced new date. The current GitHub billing docs say self-hosted runner usage is free. — [Tenki blog (vendor)](https://www.tenki.cloud/blog/github-actions-runner-pricing-2026); [GitHub Docs](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- Magic Nix Cache: Determinate Systems announced the end of the free Magic Nix Cache backend for 1 Feb 2025 because GitHub retired the old Actions cache API. It recommended FlakeHub Cache instead. — [Determinate Systems](https://determinate.systems/posts/magic-nix-cache-free-tier-eol/); [NixOS Discourse](https://discourse.nixos.org/t/end-of-life-for-the-free-tier-of-the-magic-nix-cache/59306)
- In mid-2025, Determinate brought back the magic-nix-cache-action after a community PR added support for the new cache API. Limits: it caches only between runs of one workflow in one repo, it is not a binary cache other clients can use, and performance is "decent but not great." — [Determinate Systems blog](https://determinate.systems/blog/bringing-back-magic-nix-cache-action); [NixOS Discourse](https://discourse.nixosstag.fcio.net/t/bringing-back-the-magic-nix-cache-action/65620)
- `nix-community/cache-nix-action` is mentioned in community threads as an alternative. — [NixOS Discourse thread (search result)](https://discourse.nixos.org/t/end-of-life-for-the-free-tier-of-the-magic-nix-cache/59306)
- The Determinate Nix Installer stopped offering upstream Nix (announced 10 Sep 2025; a timeline quoted in a Supabase PR gives 1 Jan 2026 as the removal date) and now installs only Determinate Nix. The Nix Installer Working Group maintains an experimental fork that installs upstream Nix. Discourse users named `cachix/install-nix-action` and nixbuild's install action as alternatives. — [Determinate blog](https://determinate.systems/blog/installer-dropping-upstream/); [NixOS Discourse](https://discourse.nixos.org/t/dropping-upstream-nix-from-determinate-nix-installer/69181?page=2)

### Inferences
- Hourly prices: GH x64 4-core $0.72/h, 8-core $1.32/h, 16-core $2.52/h. GH arm64 8-core $0.84/h, 16-core $1.56/h. GH 8-core x64 is about 3.3× the CF standard-4 baseline and about 5× a CCX33.
- A personal account cannot buy larger runners. For a single developer, GitHub-hosted means the standard runner: free and unlimited on public repos at 4 vCPU / 16 GB, or 2,000 free min (~33 h) per month on private repos at 2 vCPU / 8 GB, then $0.36/h.
- 14 GB SSD is tight for NixOS system closures and large flake builds. In practice people reclaim space by deleting preinstalled toolchains (e.g. "maximize build space" actions), but I did not source this.
- The GitHub Actions cache (10 GB per repo) is not a real Nix binary cache. Pushing to the planned R2 cache from CI is the more useful pattern. The laptops then substitute what CI built.
- Using `DeterminateSystems/nix-installer-action` now means running Determinate Nix in CI. For upstream Nix or Lix, use `cachix/install-nix-action` or similar.

### Gaps
- I did not fetch the cloud docs page that states larger runners are restricted to Team or Enterprise Cloud (only GHES copies). It is likely, but unverified for github.com in October 2026.
- The 6-hour job timeout for hosted runners and concurrency limits on Free were not verified in this session.
- I did not check the 2026 release state of `cachix/install-nix-action` or `magic-nix-cache-action`, and found no 2026-dated source on whether magic-nix-cache still works.
- GitHub's Discourse/changelog pages for the January 2026 price cut were not fetched directly. The before/after prices come from news coverage.

## Third-party GitHub runners: Ubicloud, Blacksmith, Namespace, Depot, BuildJet, RunsOn

### Takeaway
Ubicloud (German data centres, $0.0025/min for 4 vCPU and $0.005/min for 8 vCPU) and RunsOn (spot EC2 in your own AWS, about $0.0023/min for 8 vCPU, free licence for personal non-commercial use) cost about the same as or less than the CF and Hetzner baselines per hour. Blacksmith has the most useful free tier and large disks. Depot and Namespace are no cheaper than GitHub for this use. BuildJet shut down on 31 Mar 2026.

### Cited Findings
- **Ubicloud** standard x64: 2 vCPU/8 GB $0.00125/min, 4/16 $0.0025, 8/32 $0.005, 16/64 $0.010, 30/120 $0.01875. Premium x64 costs about 1.6× that (8 vCPU $0.008/min, 16 vCPU $0.016/min). New users get premium by default and can switch it off. arm64: 4 vCPU/12 GB $0.0025, 8/24 $0.005, 16/48 $0.010. $2.50/month free credit (= 1,250 standard 2-vCPU minutes). VMs run in German data centres. Disk size is not stated, only "local block storage." — [Ubicloud pricing docs](https://www.ubicloud.com/docs/about/pricing)
- **Blacksmith**: Ubuntu x64 $0.004/min, ARM $0.0025/min (the 2-vCPU base rate), 3,000 free min/month. Larger sizes consume minutes in proportion to vCPU count (a 4-vCPU job uses 2× minutes). An ARM minute counts as 0.625 x64 minutes. Sticky disks cost $0.50/GB/month. — [Blacksmith pricing](https://www.blacksmith.sh/pricing); [Blacksmith docs](https://docs.blacksmith.sh/blacksmith-runners/overview)
- **Blacksmith** sizes (x64): 2 vCPU/8 GB/80 GB, 4/16/80 GB, 8/32/160 GB, 16/64/750 GB, 32/128/1.5 TB. ARM: 4/12/75 GB, 8/24/160 GB, 16/48/750 GB. Regions include eu-central (Frankfurt) and eu-west (Amsterdam). — [Blacksmith docs](https://docs.blacksmith.sh/blacksmith-runners/overview)
- **Namespace**: Developer plan $0/month pay-as-you-go, max 3 h per instance, 32 vCPU Linux concurrency. 1 unit-minute = 1 vCPU + 2 GB for 1 minute, about $0.001/vCPU-min prepaid or $0.0015/vCPU-min overage. Shapes with more RAM cost more (4 vCPU/16 GB = $0.008/min prepaid). Team plan is $100/month with 100,000 unit-minutes. Cache volumes on Developer: $0.002/GB-hr snapshots and $0.0048/GB-day storage. 30-day free trial. — [Namespace pricing](https://namespace.so/pricing)
- **Depot**: Developer plan $20/month including 2,000 GitHub Actions minutes and 25 GB cache, then $0.006/min. Runner rates (per-second, converted): 2 vCPU/8 GB $0.006/min, 4/16 $0.012, 8/32 $0.024, 16/64 $0.048. The page does not clearly attribute this table to Actions runners. arm64 runner pricing is not stated. — [Depot pricing](https://depot.dev/pricing)
- **BuildJet** announced on 6 Feb 2026 that it was shutting down. It stopped running jobs on 31 Mar 2026. — [RunsOn blog (competitor)](https://runs-on.com/blog/buildjet-shutting-down-runson-alternative/); [WarpBuild blog (competitor)](https://www.warpbuild.com/blog/buildjet-shutting-down)
- **RunsOn**: free licence for "non-profit, open-source and personal non-commercial projects" in exchange for a public link back. Commercial licences start at €300/year. You pay AWS directly for EC2 (spot, per-second, no markup) and a control plane (about $7/month). Example spot costs, us-east-1, including a 30 GB gp3 root volume: x64 4 vCPU (m8a.xlarge) $0.0015/min, 8 vCPU (c8id.2xlarge) $0.0023/min, 16 vCPU (c8id.4xlarge) $0.0044/min. arm64 4 vCPU $0.0016, 8 vCPU $0.0028, 16 vCPU $0.0047/min. Disk size and throughput are configurable. — [RunsOn pricing](https://runs-on.com/pricing/)

### Inferences
- Per hour at 8 vCPU (x64): Ubicloud standard $0.30 (premium $0.48), RunsOn spot about $0.14 + $7/month fixed, Blacksmith about $0.96 (4× the 2-vCPU rate), Namespace overage about $0.72 (8 vCPU with 16 GB; more RAM costs more), Depot $1.44, GitHub $1.32. The baselines are CCX33 €0.22/h at 8 vCPU / 32 GB and CF standard-4 $0.40/h at 4 vCPU.
- At 16 vCPU: Ubicloud $0.60/h, RunsOn spot about $0.26/h, Blacksmith about $1.92/h, GitHub $2.52/h.
- Monthly cost at 100 builder-hours on 8 vCPU: Ubicloud about $30, RunsOn about $14 + $7, Blacksmith about $96 minus the free tier (3,000 2-vCPU minutes = 12.5 h at 8 vCPU), GitHub $132. At 5–20 h/month, the free tiers of Blacksmith (12.5 h at 8 vCPU) and Ubicloud ($2.50) cover much or all of the use.
- Nix suitability: Blacksmith's large disks (160 GB at 8 vCPU) and sticky disks fit a Nix store better than GitHub's 14 GB. A sticky disk could hold a persistent `/nix/store`, but I did not verify this works with Nix. Ubicloud's German location suits an R2 or EU workflow. RunsOn gives full control (custom AMI, disk size, arm64 Graviton) but needs an AWS account and some setup.
- All of these are GitHub Actions runners. They run jobs triggered by push, PR or `workflow_dispatch`. They cannot be used as a `nix.buildMachines` / `ssh-ng://` remote builder from a laptop. Laptops benefit only indirectly, by substituting from the binary cache after CI has pushed. Local, uncommitted changes still build locally. That is the core trade-off against CF Containers, Hetzner, or a home box reached over SSH.

### Gaps
- Blacksmith's per-size prices are inferred from its proportional-minutes rule, not listed directly.
- Ubicloud disk sizes are not published on the pricing page.
- Depot's runner table may belong to another product (the page is ambiguous).
- I found no Nix-specific documentation or user reports for these vendors in this session, such as KVM availability for NixOS VM tests or support for a persistent `/nix` volume.
- RunsOn prices are for us-east-1. EU (eu-central-1) spot prices were not checked.

## Self-hosted CI on own machine: buildbot-nix, Hydra, GitHub self-hosted runners on NixOS

### Takeaway
buildbot-nix is the Nix-native option for a single developer with GitHub repos. It is a NixOS module with a GitHub App, PR status checks, and parallel evaluation of `.#checks` via nix-eval-jobs. It can run on the same box that serves as an SSH remote builder, so one machine does both jobs. GitHub self-hosted runners remain free.

### Cited Findings
- buildbot-nix is a NixOS module. It evaluates flakes in parallel with nix-eval-jobs (each `.#checks` attribute is a build step) and keeps a shared Nix store with GC protection for the last build. — [buildbot-nix README](https://github.com/nix-community/buildbot-nix)
- It authenticates as a GitHub App, which gives automatic webhooks and commit status. It builds PRs and the default branch, and supports GitHub login and Gitea at the same time. — [buildbot-nix README](https://github.com/nix-community/buildbot-nix)
- Cache push: Cachix is supported natively. Attic is not native (the workaround is a systemd watcher that uploads). Harmonia is recommended for serving a local cache. The README does not mention niks3. — [buildbot-nix README](https://github.com/nix-community/buildbot-nix)
- Master and worker can run on one machine. Other architectures can be added through Nix remote builders. Experimental Hercules-CI-style "effects" can run deployments. The lix overlay is incompatible (use `nix.package = pkgs.lix` instead). The README says it is under active development. — [buildbot-nix README](https://github.com/nix-community/buildbot-nix)
- GitHub self-hosted runners are free. The proposed $0.002/min fee was postponed and has not been reintroduced. — [GitHub Docs](https://docs.github.com/en/billing/concepts/product-billing/github-actions); [Techzine](https://www.techzine.eu/news/devops/137396/github-bends-to-criticism-and-delays-paid-self-hosting-of-runners/)

### Inferences
- A home box running buildbot-nix (or a GitHub runner via the NixOS `services.github-runners` module, not sourced here) covers both modes. It builds on push for CI and accepts `ssh-ng://` builds from the laptops. No hosted runner can do the second.
- Pushing to R2 needs either a post-build hook that runs `nix copy --to s3://...` (generic Nix, not buildbot-specific) or Cachix. buildbot-nix does not have native S3 push.

### Gaps
- I gathered no 2026 information on Hydra, such as maintenance state or suitability for one user. It is usually considered heavier to run than buildbot-nix, but that is unsourced here.
- I did not verify the NixOS `services.github-runners` module options in this session.
- I did not look for buildbot-nix release dates or 2026 changelog entries.

## Home server: hardware cost, RAM prices, power, exposure, amortisation

### Takeaway
DDR5 prices in October 2026 are very high: a 64 GB DDR5-5600 SO-DIMM kit costs €999 on geizhals (13 Oct 2026). That drives the cost of a 64 GB mini PC builder. Power is cheap by comparison, at about €3–6/month at German prices (~37 ct/kWh). Amortised over 3 years, a new 64 GB Ryzen mini PC costs roughly €45–60/month. That is more than ~100 h/month on a CCX33 (~€22) or Ubicloud. The home box only wins if RAM or hardware is already owned, or use is heavy.

### Cited Findings
- Crucial 64 GB DDR5-5600 SO-DIMM kit (CT2K32G56C46S5): lowest price €999.00, "Preis vom 13.10.2026." — [geizhals.de](https://geizhals.de/crucial-so-dimm-kit-64gb-ct2k32g56c46s5-a2988656.html)
- Crucial 64 GB DDR5-4800 SO-DIMM kit: from €689, price data from 7–8 Aug 2026, with no offers at the time of the search. — [geizhals.de (via search snippet)](https://geizhals.de/crucial-so-dimm-kit-64gb-ct2k32g48c40s5-a2682438.html)
- Caseking lists 64 GB (2×32) DDR5 desktop kits at about €600–1,392. The page is undated. — [Caseking (via search snippet)](https://www.caseking.de/en/pc-components/memory/ddr5)
- Mini PC barebones (US listings, dates unclear): Minisforum UM890 Pro (Ryzen 9 8945HS) about $463–799 on Newegg. Acemagic F3A (Ryzen AI 9 HX 370) barebone $719 in a 2025 sale. Minisforum AI X1 Pro-370 $1,179. GEEKOM A9 Max $1,499–1,599. — [Newegg](https://www.newegg.com/p/pl?N=100008345+601453674); [Slickdeals](https://slickdeals.net/f/18133174-acemagic-f3a-barebone-mini-pc-ryzen-ai-9-hx-370-2x-ddr5-so-dimm-2x-usb4-type-c-w-free-8-in-1-docking-hub-719); [GEEKOM](https://www.geekompc.com/geekom-a9-max-mini-pc/)
- Power: a 2026 roundup gives about 9 W idle and 86 W load for the Minisforum X1 Pro-370 (HX 370), and about 8 W idle for Ryzen 7 255 models. It states no methodology. Another guide says 12–15 W idle, which contradicts it. — [minipclab.com](https://minipclab.com/blog/best-ryzen-ai-mini-pc); [Alibaba buying guide (low quality)](https://electronics.alibaba.com/buyingguides/mini-pc-ryzen-9-guide-which-model-fits-your-real-needs)
- German household electricity 2026: BDEW about 37.0 ct/kWh (April 2026, confirmed in August data). Destatis 37.97 ct/kWh for H1 2026, across all contracts. New-customer tariffs are much lower (22.7–27.7 ct/kWh, Check24/Strom-Report). — [Finanztip](https://www.finanztip.de/strompreis/); [Check24](https://www.check24.de/strom/strompreisentwicklung/); [Strom-Report](https://strom-report.com/news/strompreise-2026-auf-niedrigstem-niveau-seit-jahren/)

### Inferences
- Example build: Ryzen 9 8945HS barebone (about €450–700, extrapolated from US prices) + 64 GB DDR5-5600 €999 + 2 TB NVMe (~€150, not sourced) ≈ €1,600–1,850. Over 36 months that is ≈ €44–51/month before power. A ready-made 64 GB HX 370 unit (~€1,200–1,600) gives ≈ €33–45/month.
- Power at 37 ct/kWh: idle 24/7 at 9 W ≈ 6.6 kWh ≈ €2.40/month. 100 h at 86 W load adds ≈ 8.6 kWh ≈ €3.20. Total ≈ €3–6/month. Even at a pessimistic 15 W idle, it stays under €8/month.
- Total ≈ €40–60/month for a new 64 GB mini PC. Break-even against a CCX33 (€0.22/h) is about 200–270 builder-hours/month, above the stated 5–100 h. At low use, the case for a home box is non-monetary: an always-warm local `/nix/store`, an SSH remote builder without cold-start, and no egress or per-hour billing. Alternatives are 32 GB RAM (about half the RAM cost, enough for most builds except large Rust/LLVM/Chromium), or an existing desktop or used workstation with RAM bought before the price spike.
- The 2026 RAM spike reverses the old picture, where a home box was the clearly cheap option. Selling or reusing existing DDR5 SO-DIMMs from laptops changes the calculation a lot.
- Exposure: putting the box on a Tailscale tailnet (or WireGuard) and adding it to `nix.buildMachines` on the laptops, with no inbound port forwarding, is the standard pattern. Webhooks for buildbot-nix would need either a tunnel (e.g. Cloudflare Tunnel or Tailscale Funnel) or polling. I did not source these claims or Tailscale's 2026 free-plan limits in this session.

### Gaps
- No EUR-denominated, dated October 2026 prices for mini PC barebones in Germany (geizhals listings for UM890 Pro or HX 370 barebones were not fetched).
- No independent wall-power measurements (e.g. ComputerBase, notebookcheck) for the 8945HS or HX 370 under sustained all-core Nix builds. Sustained power may exceed the 86 W figure.
- No used-market prices (Kleinanzeigen, refurbished workstations).
- No sourced numbers for Tailscale's free plan in 2026 or for home upload bandwidth effects when pushing to R2.
- The cause of the RAM price spike and its outlook were not researched. The geizhals price-history chart was not readable via fetch.
