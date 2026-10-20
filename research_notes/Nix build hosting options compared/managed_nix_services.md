# Managed Nix-specific build and cache services (status October 2026)

Baselines for comparison: Cloudflare Containers standard-4 (4 vCPU, 12 GiB) at about $0.40/h, which is about $0.80 per 8-vCPU-hour; Hetzner CCX33 (8 dedicated vCPU, 32 GB) at about €0.22/h. Pages were fetched on 2026-10-12. Most pricing pages show no effective date.

## nixbuild.net: pricing, free allowance, limits, architectures, remote-builder model, cache

### Takeaway
nixbuild.net is the only service found that works as a transparent SSH remote builder (`nix.buildMachines` / `--builders`) with per-use billing. It costs €0.12 per CPU-hour after 25 free CPU-hours per month. An 8-vCPU-hour costs €0.96, about 4x the price of an on-demand CCX33. There is no idle cost and no machine lifecycle to manage. Darwin is not supported.

### Cited Findings
- Price: €0.12 per CPU-hour excl. VAT, charged only after the monthly free allowance is used. Billing is monthly through Stripe. Unused months cost nothing. — [nixbuild.net](https://nixbuild.net/)
- Free allowance: 25 CPU-hours per month per account. Signup needs no credit card. Billing must be enabled in the nixbuild.net shell before usage beyond the free hours. — [nixbuild.net](https://nixbuild.net/)
- Vendor example: about 30 CPU-hours (roughly 130 packages, a kernel rebuild after a stdenv change) costs about €3.60. — [nixbuild.net](https://nixbuild.net/)
- CPU: 1–16 vCPUs are allocated automatically per build. Each vCPU is a dedicated hyperthread. The upper limit may change. — [nixbuild.net](https://nixbuild.net/)
- Memory: no formal limit. A build that runs out of memory restarts automatically with more memory. Builds run entirely in memory, so intermediate artifacts count toward memory. Repeated excessive use may lead to contact from the operator. — [nixbuild.net](https://nixbuild.net/)
- Maximum build duration: not stated. — [nixbuild.net](https://nixbuild.net/)
- Architectures: x86_64-linux, i686-linux, aarch64-linux, armv7l-linux. KVM-in-build (for NixOS VM tests) is in Early Access. Darwin is not listed. — [nixbuild.net](https://nixbuild.net/)
- Integration: a standard Nix SSH remote builder; accounts are managed through an SSH text shell. There is an official GitHub Action (nixbuild-action), Hydra worker use with many concurrent jobs, and an API. — [nixbuild.net](https://nixbuild.net/)
- Cache: nixbuild.net is not a public substituter. It fetches from Nix caches and reuses build results within an account. It can upload results to your own cache or a third-party cache, including directly from a build. — [nixbuild.net](https://nixbuild.net/)
- Privacy: each build runs in a KVM sandbox with no network and no disk access. Dependencies and results are shared only within the account or with accounts you explicitly trust. Hosting is in Germany. Retention of results has no publicly stated limit. Private enterprise deployments are available by contacting sales. — [nixbuild.net](https://nixbuild.net/)
- Status: the site footer reads © 2025. The founder presented "Remote Nix builds" at SCALE 22x in March 2025. A search found no 2026 announcements. — [nixbuild.net](https://nixbuild.net/); [SCALE 22x talk](https://www-test.socallinuxexpo.org/scale/22x/presentations/remote-nix-builds)

### Inferences
- An 8-vCPU-hour costs 8 × €0.12 = €0.96. The free tier covers about 3 such hours per month.
  - At 5 builder-hours on 8 vCPU (40 CPU-h): (40−25) × €0.12 = €1.80/month.
  - At 100 builder-hours on 8 vCPU (800 CPU-h): about €93/month. A CCX33 for the same 100 h costs about €22.
- Billing counts only CPU used by builds, not wall-clock time of a VM, so idle and eval time is free. Real costs may be lower than the 8-vCPU-hour figure, because many derivations are single-threaded and get small allocations.
- Of the services found, this is the closest fit for "transparent via nix.buildMachines". Results stay private to the account, but they must be pushed to the user's R2 cache explicitly (for example with a post-build hook or `nix copy`).

### Gaps
- The pricing page gives no effective date. Dates of recent price or feature changes are unknown.
- No 2025–2026 changelog was found, so liveness rests on the site's © 2025 footer.
- No 2026 information was found on KVM leaving Early Access, on aarch64 capacity, or on new regions.

## Garnix: CI + cache for flakes; free tier; paid plans; private repos; hosting

### Takeaway
Garnix is a GitHub-integrated flake CI. It builds every flake output on push and uploads the results to its cache, which supports public and private caches. Garnix also hosts NixOS servers. Plans are Free (1,500 CI minutes/month) and Individual ($25/month, 10,000 minutes). Extra minutes cost $0.006 each. Garnix is CI-on-push, not a `--builders` target.

### Cited Findings
- Free: $0/month, 1,500 CI minutes/month, 500 PR-deployment minutes/month, public and private binary cache, 2-month trial of 1 server deployment. — [garnix pricing](http://garnix.io/pricing/)
- Individual: $25/month, 10,000 CI minutes and 10,000 PR-deployment minutes, public and private cache, 1 server. — [garnix pricing](http://garnix.io/pricing/)
- Enterprise: contact sales. Unlimited minutes, on-premise hosting, custom CI domain. — [garnix pricing](http://garnix.io/pricing/)
- Extra minutes: $0.006 per minute (= $0.36/h) for CI and PR deployments. — [garnix pricing](http://garnix.io/pricing/)
- Extra hosting machines per month, each with 20 TB traffic: i2x4 (2 vCPU/4 GB/40 GB) $15; i4x8 $30; i8x16 (8 vCPU/16 GB/160 GB) $60; i16x32 $120. Raising the machine limit requires emailing support. — [garnix pricing](http://garnix.io/pricing/)
- Every build output is uploaded to the garnix cache. The cache can serve developer machines and servers. Hosting deploys NixOS onto VMs with zero downtime, and PR preview deployments shut down when the PR closes. — [garnix.io](https://garnix.io/)
- Architectures: the homepage example flake builds `x86_64-linux` and `aarch64-darwin`. A template's garnix.yaml enables aarch64-darwin and x86_64-linux. No supported-systems list was found on the current pages. — [garnix.io](https://garnix.io/); [srid.ca template](https://srid.ca/haskell-template/garnix)
- Private repos: a September 2023 release added support for private flake inputs. Before that, private repos worked only without private dependencies. Badges don't work for private repos. — [garnix release notes 2023-09-04](https://garnix.io/blog/september-4-2023-release-notes/)
- Integration: GitHub only. The docs say garnix is set up "for your GitHub repos". The docs landing page mentions no remote-builder mode. — [garnix docs](http://garnix.io/docs/)

### Inferences
- $0.36 per CI hour is cheap, but the CI machine size is not published, so a cost per 8-vCPU-hour cannot be computed.
- With the Individual plan's 10,000 minutes (about 167 h) for $25, the effective rate is about $0.15/h, assuming the user's 5–100 h/month fits within it.
- Garnix fits flake projects hosted on GitHub. For clan-core machines it can build `nixosConfigurations` on push and serve them from its cache. It does not replace a remote builder for ad-hoc local `nix build`.
- Hosting at $60/month for 8 vCPU/16 GB is an always-on VM, not on-demand compute.

### Gaps
- No current documentation was found for CI machine specs (vCPU/RAM), build timeouts, or cache storage limits.
- aarch64-linux support was not confirmed.
- Darwin support for private repos was not confirmed.
- Pages carry no dates, and no 2025–2026 news was retrieved.
- No support was found for non-GitHub forges (Codeberg, Forgejo).

## Cachix: cache tiers, private caches, Cachix Deploy, build offering

### Takeaway
Cachix is a binary-cache-only service with Cachix Deploy agents. It has no hosted build offering. As of October 2026, the pricing page lists no prices, only "contact" per tier. Open-source projects get 5 GB free.

### Cited Findings
- Tiers: Starter 50 GiB / Deploy 100 agents; Standard 250 GiB / 200 agents / 1-hour consultation; Pro 1,500 GiB / 1,000 agents. All tiers have unlimited bandwidth and Cloudflare CDN. Prices say "Please contact" for every tier. — [Cachix pricing](https://www.cachix.org/pricing)
- Free: 5 GB for open source. Free users get 20 Deploy agents. — [Cachix pricing](https://www.cachix.org/pricing)
- Storage behavior: entries are compressed (vendor claims up to 90% savings). Paths from cache.nixos.org are not stored. A warning email is sent at 85% of the limit, and least-recently-used entries are evicted at the limit. — [Cachix pricing](https://www.cachix.org/pricing)
- Terms: 14-day trial, one free month on annual plans, 30-day billing cycles. A self-hosted option is available by contacting sales. — [Cachix pricing](https://www.cachix.org/pricing)
- No hosted builders or runners are mentioned. — [Cachix pricing](https://www.cachix.org/pricing)

### Inferences
- Hiding prices behind "contact" is a change from earlier public per-tier prices, which I remember from before this research but could not verify. This may signal a move toward enterprise sales. Treat any older list price as stale.
- For a single developer who already has an R2 cache (no egress fees), Cachix adds little except signing, a CDN, and Deploy.

### Gaps
- No current numeric prices exist. Whether private caches are included on all paid tiers is not stated on the page.

## Determinate Systems: FlakeHub Cache, Determinate Nix, magic-nix-cache, any build service

### Takeaway
Determinate sells one platform bundle (Determinate Nix + FlakeHub with FlakeHub Cache + Secure Packages) starting at $7 per device per user per month. FlakeHub Cache is paid-only. Only trusted CI runners can push to it (GitHub Actions, GitLab CI, Semaphore, Buildkite); ad-hoc pushes from a laptop or remote builder are not allowed. magic-nix-cache was deprecated in early 2025 but revived in June 2025. No Determinate build service was found.

### Cited Findings
- Pricing: "$7 per device, per user, per month" as the starting price, one price for Determinate Nix, Determinate Secure Packages, and FlakeHub. Larger teams contact sales. The page appeared in search results, but direct fetches of determinate.systems/pricing returned HTTP 404 on 2026-10-12. — [Determinate pricing (search result)](https://determinate.systems/pricing)
- FlakeHub Cache is available only on paid plans. — [FlakeHub Cache docs](https://docs.determinate.systems/flakehub/cache)
- Push model: "only trusted builders are allowed to push to the cache". The trusted builders are GitHub Actions, GitLab CI/CD, Semaphore, and Buildkite runners. — [FlakeHub Cache docs](https://docs.determinate.systems/flakehub/cache)
- Auth: JWT from CI identity providers; `determinate-nixd login` on workstations. Read access is controlled per flake. The cache is unavailable to PRs from forks. — [FlakeHub Cache docs](https://docs.determinate.systems/flakehub/cache)
- FlakeHub Cache launched as a private beta in March 2024. — [Determinate blog](https://determinate.systems/blog/flakehub-cache-beta)
- magic-nix-cache: the free tier was announced to wind down by 1 February 2025 because GitHub changed its Actions cache API. In June 2025 Determinate announced the action is back, built on a reverse-engineered API that "could break at any time". FlakeHub Cache is still recommended for most uses. — [Determinate blog: Bringing back Magic Nix Cache](https://determinate.systems/blog/bringing-back-magic-nix-cache-action); [NixOS Discourse](https://discourse.nixosstag.fcio.net/t/bringing-back-the-magic-nix-cache-action/65620)
- A third-party repo bumped magic-nix-cache-action to v14 in May 2026. This was not verified beyond that log. — [gitea.com log](https://gitea.com/techknowlogick/tklk-flake/actions?page=8)
- Build service: none found. A Determinate engineer gave a talk on remote builders, but no product was announced. — [Sessionize talk](https://sessionize.com/s/tristan-ross/using-remote-builders-in-nix/156855)

### Inferences
- FlakeHub Cache doesn't fit a remote-builder-plus-own-cache setup: builds from nixbuild.net, Hetzner, or Cloudflare cannot push to it. It fits only if builds run in a supported CI.
- At $7/device/user/month, a single user with several clan machines may pay per device. How "device" is counted is unclear.

### Gaps
- The full pricing page could not be fetched (404). Storage limits, how devices are counted, and whether a free tier exists for private flakes are unverified.
- Current magic-nix-cache status is known only from the June 2025 post plus one 2026 log.

## Namespace.so: Nix-capable runners/builders, pricing

### Takeaway
Namespace is a general CI-compute vendor with an early-access Nix integration. It offers a `nixcache` proxy backed by Namespace storage and documents how to use its instances as SSH remote builders. The remote-builder setup is manual (create instance, install Nix, run nixcache), not a turnkey builder endpoint. Linux 8 vCPU/32 GB costs $0.016/min prepaid ($0.96/h) or $0.024/min overage ($1.44/h). Namespace is the only service found that offers macOS compute.

### Cited Findings
- Plans: Developer $0 pay-as-you-go (max instance duration 3 h, concurrency 32 Linux / 12 macOS vCPU); Team $100/month with 100,000 unit-minutes (5 h max); Business $250/month with 250,000 unit-minutes (up to 24 h). 30-day trial, no card needed. — [Namespace pricing](https://namespace.so/pricing)
- Unit-minutes = vCPU × minutes × multiplier: Linux 1×, Windows 2×, Linux on Apple Silicon 7×, macOS 10×. — [Namespace pricing](https://namespace.so/pricing)
- Linux rates (prepaid / overage per minute): 4 vCPU/16 GB $0.008/$0.012; 8 vCPU/32 GB $0.016/$0.024; 16 vCPU/64 GB $0.032/$0.048. ARM64 is priced like x86 per a third-party summary. — [Namespace pricing](https://namespace.so/pricing); [cicdpipelinecost.com](https://cicdpipelinecost.com/namespace-pricing)
- Linux on Apple Silicon (arm64, early access): 8 vCPU/32 GB costs $0.112/$0.168 per min. macOS 8 vCPU/14 GB costs $0.08/$0.12 per min. — [Namespace pricing](https://namespace.so/pricing)
- Cache volumes: Developer pays $0.002/GB-hr for snapshots and $0.0048/GB-day for storage. Team and Business include free allowances. — [Namespace pricing](https://namespace.so/pricing)
- Nix integration (early access; contact support for a cache namespace): `nixcache` is a local HTTP substituter proxy on 127.0.0.1:18765 for Linux and macOS on amd64 and arm64. Publishing requires `nix copy` with your own signing key. Remote builders: `nsc create --bare --ssh_key`, then install Determinate Nix, run nixcache, start nix-daemon, and on the client set distributed builds with `builders-use-substitutes = true`. The docs give no builder limits or pricing. — [Namespace Nix docs](https://namespace.so/docs/integrations/nix)
- A Better Stack comparison lists different plan prices (Developer $20, Startup $200). These look like another vendor's numbers and conflict with Namespace's own page. — [Better Stack](https://betterstack.com/community/comparisons/namespace-alternatives.md)

### Inferences
- An 8-vCPU-hour costs $0.96 (prepaid) to $1.44 (overage). The pricing page does not say which rate Developer pay-as-you-go uses. Either rate is above the Cloudflare baseline (~$0.80) and well above Hetzner (€0.22).
- The Developer plan's 3 h instance limit and the manual bootstrap make Namespace a scripted ephemeral builder, much like the Hetzner approach, not a transparent always-available builder.
- macOS at $4.80/h (8 vCPU) is the only managed darwin option found besides garnix's CI-on-push.

### Gaps
- No public figure for the time from instance creation to SSH-ready.
- The pricing page has no effective date.
- The nixcache early-access terms are unknown.

## Hercules CI, Hydra-as-a-service, buildbot-nix hosted, nix-community builders, newer services (2024–2026)

### Takeaway
Hercules CI is still listed (free for open source, €29/month for private repositories), but you supply the agents and compute. Among hosted services, NixCI (nix-ci.com) is the notable newer entrant: hosted workers at 0.27 CHF per worker-hour plus 30 CHF per developer per month for private repos. nix-community builders exist but forbid private or secret builds. No hosted Hydra or buildbot-nix offering was found.

### Cited Findings
- Hercules CI: free for open source (unlimited agents and builds); €29/month for public and private repos with unlimited builds and agents; Enterprise by quote. The agent is open source (Apache-2.0) and does evaluation and builds on your own machines. hercules-ci.com coordinates jobs and GitHub integration. — [Hercules CI](https://hercules-ci.com/); [hercules-ci-agent on Hackage](https://hackage-origin.haskell.org/package/hercules-ci-agent)
- The Hercules CI pricing page returned no content when fetched, so the €29 figure comes from a search snippet of the homepage. — [Hercules CI](https://hercules-ci.com/)
- NixCI: FOSS free (own workers, or hosted workers at 0.27 CHF/h ≈ $0.33/€0.29); Hosted plan 30 CHF/developer/month plus 0.27 CHF/worker-hour, unlimited private repos, GitHub, GitLab, and Forgejo; Self-hosted by quote. Billing is per second of job execution. A "developer" is someone who pushes at least 3 commits to private repos in a month. 14-day trial. — [NixCI pricing](https://nix-ci.com/pricing)
- nix-community builders: x86_64-linux, x86_64-freebsd, aarch64-linux, aarch64-darwin. Access is for well-known community members only. The rules forbid private data and secret builds and warn not to trust results. — [nix-community builders](https://nix-community.org/community-builders/)

### Inferences
- NixCI worker size is not published, so the 8-vCPU-hour cost cannot be computed. If one worker were 8 vCPU, the cost would be about $0.33/h plus the per-seat fee.
- NixCI supports Forgejo, which suits a self-hosted forge. It is still CI-on-push, not a remote builder.
- Hercules CI adds coordination only. Compute still needs Hetzner, Cloudflare, or similar.
- nix-community builders are unsuitable for private clan configurations, which contain secrets.

### Gaps
- No hosted Hydra or hosted buildbot-nix offering was found. Search coverage was limited.
- The operator of NixCI, its maturity, and its worker specs and architectures are not stated on the pricing page.
- Hercules CI shows no 2025–2026 activity in what was retrieved, so its maintenance status is unverified.

## Compute cost per 8-vCPU-hour equivalent

### Takeaway
Among managed options, nixbuild.net (€0.96) and Namespace (prepaid $0.96, overage $1.44) both cost more per 8-vCPU-hour than the Cloudflare (~$0.80) and Hetzner CCX33 (€0.22) baselines. nixbuild.net bills only CPU that builds actually use and has no idle time, so at low usage (≤ 25 CPU-h/month) it is free. Garnix and NixCI are cheap per hour, but their machine sizes are undisclosed.

### Cited Findings
- nixbuild.net: €0.12/CPU-h, so 8 vCPU-h = €0.96. First 25 CPU-h/month free. — [nixbuild.net](https://nixbuild.net/)
- Namespace Linux 8 vCPU/32 GB: $0.016/min = $0.96/h prepaid; $0.024/min = $1.44/h overage. arm64 (Apple Silicon) 8 vCPU: $6.72/h prepaid. macOS 8 vCPU: $4.80/h prepaid. — [Namespace pricing](https://namespace.so/pricing)
- Garnix: $0.006/min = $0.36/h for extra minutes, machine size not stated. Individual plan: $25 for 10,000 min ≈ $0.15/h. — [garnix pricing](http://garnix.io/pricing/)
- NixCI: 0.27 CHF/worker-hour, worker size not stated, plus 30 CHF/developer/month for private repos. — [NixCI pricing](https://nix-ci.com/pricing)
- Cachix, FlakeHub, and Hercules CI sell no compute. — [Cachix pricing](https://www.cachix.org/pricing); [FlakeHub Cache docs](https://docs.determinate.systems/flakehub/cache); [Hercules CI](https://hercules-ci.com/)

### Inferences
Monthly cost estimates use list prices with no idle overhead and assume full 8-vCPU use:

| Service | 5 h/month | 100 h/month |
|---|---|---|
| nixbuild.net | ~€1.80 | ~€93 |
| Namespace prepaid | ~$4.80 | ~$96 |
| Hetzner CCX33 | ~€1.10 | ~€22, plus boot overhead |
| Cloudflare | ~$4 + $5 | ~$80 + $5 |

- Real nixbuild.net costs are likely lower, because builds rarely use all 8 vCPUs and billing is per CPU actually allocated.

### Gaps
- No vendor states a vCPU type (dedicated core vs hyperthread) except nixbuild.net, which uses one dedicated hyperthread per vCPU. Like-for-like performance per vCPU is unknown.
- The CI machine specs for Garnix and NixCI are unpublished, so their per-8-vCPU-hour figures cannot be computed.
