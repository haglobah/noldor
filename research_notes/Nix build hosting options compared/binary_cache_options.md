# Binary cache storage options for Nix (as of 2026-10-12)

Scenario: one developer, 50–500 GB cache, a handful of personal machines plus maybe CI as readers, an ephemeral builder as the writer.

## Cloudflare R2: prices, free tier, public access, Nix integration, private access

### Takeaway
R2 costs $0.015/GB-month with zero egress, and its free tier covers 10 GB, 1M writes and 10M reads per month. At 50–500 GB that is about $0.60–$7.35/month for storage, and request costs are negligible at personal scale. Serve reads from a custom domain, not r2.dev. For a private cache, use Cloudflare Access/WAF token auth on the custom domain, or a read proxy such as niks3's.

### Cited Findings
- Standard storage $0.015/GB-month. Infrequent Access $0.01/GB-month plus a $0.01/GB retrieval fee — [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- Class A (writes/lists) $4.50 per million (IA $9.00). Class B (reads) $0.36 per million (IA $0.90) — [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- Monthly free tier: 10 GB-month storage (Standard only), 1M Class A, 10M Class B — [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- Egress is free for both storage classes, whether served through the Workers API, the S3 API or r2.dev. Other metered services attached to the bucket may still charge — [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- r2.dev public access is "rate-limited and should only be used for development purposes". Cloudflare does not support CNAMEs to r2.dev. Production use needs a custom domain whose zone is in the same Cloudflare account; non-Cloudflare domains can use a partial (CNAME) setup — [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- WAF custom rules, caching, access controls and Bot Management require a custom domain; r2.dev offers none of them. Cache Everything is needed to cache all file types (e.g. `.narinfo`, `.nar.zst`). Smart Tiered Cache is suggested — [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- Private access options on a custom domain: Cloudflare Zero Trust Access, or WAF Token Authentication. With either, also disable the r2.dev URL, or the bucket "will remain publicly available through your r2.dev subdomain" — [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- The Nix S3 store takes `endpoint`, `region` (default `us-east-1`), `profile`, `scheme`, `addressing-style`, compression, multipart and `secret-key` settings. Credentials come from the AWS SDK default chain (env vars, `~/.aws` files). For anonymous public caches the manual recommends using the bucket's `https://` URL as an HTTP binary cache instead of `s3://`. The page is for Nix 2.35.2 and does not mention R2 — [Nix manual: S3 binary cache store](https://nix.dev/manual/nix/latest/store/types/s3-binary-cache-store)
- The niks3 wiki (edited 2026-09-01) rates R2 "Excellent" and its top recommendation. It notes native Content-Encoding (zstd) support and a built-in CDN. In its 1 TB stored + 10 TB/month downloaded scenario, R2 costs $15/month — [niks3 wiki: S3 Provider Comparison](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)
- The Attic config template gives an R2 endpoint as its example: `endpoint = "https://xxx.r2.cloudflarestorage.com"` — [attic config-template.toml](https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/config-template.toml)
- niks3's optional read proxy (`--enable-read-proxy`) serves private buckets with its own credentials. `--read-redirect-ttl` answers NAR requests with a 307 to a presigned URL, and anyone holding that URL can fetch the object until it expires — [niks3 README](https://github.com/Mic92/niks3)

### Inferences
- Write path: `nix copy --to 's3://BUCKET?endpoint=<accountid>.r2.cloudflarestorage.com&region=auto&secret-key=…'` (R2 uses region `auto`; this comes from general R2 S3 compatibility, not from the Nix manual). Read path: `https://cache.example.com` as a plain HTTP substituter.
- Cost at 500 GB: (500 − 10) × $0.015 ≈ $7.35/month. A large closure upload is about 1–3 Class A operations per path (narinfo + NAR, multipart for >100 MB). That fits inside the 1M free writes unless pushes are very frequent.
- Private-access options: (a) Cloudflare Access service tokens. Nix can send them only as headers, so this needs testing; netrc carries only basic auth. (b) A Worker in front of the bucket that checks basic auth, which Nix supports via `netrc-file`. (c) niks3's read proxy. Option (b) is the most Nix-native. This is my design inference; I found no Cloudflare doc specific to Nix.

### Gaps
- I did not find an official doc or Discourse post on the Worker + basic auth pattern for Nix in 2026. I did not verify whether Cloudflare Access service-token headers can be injected into Nix substituter requests.
- I did not verify whether Cloudflare's CDN terms limit caching of large binary files on a free zone. The custom domain path is generally used for this, but I have no source for that.

## Alternatives: Backblaze B2, Hetzner, AWS S3, Wasabi, Scaleway, Tigris

### Takeaway
At 50–500 GB with low egress, every option costs single-digit dollars a month except AWS S3, which is cheap to store but costly to serve. B2 and Wasabi are cheaper per GB than R2 but need Cloudflare in front for free egress, and B2 also needs a header fix. Wasabi bills a 1 TB minimum and 90-day minimum retention, which hurts a GC'd cache. Hetzner is now €6.49/month base after the 2026 increase, and the niks3 author measured it as too slow for narinfo lookups. Tigris matches R2's zero egress but costs $0.02/GB.

### Cited Findings
**Backblaze B2**
- Storage from $6.95/TB/month, first 10 GB free. Free egress up to 3× average monthly storage, then $0.01/GB. Unlimited free egress to or through partner CDNs, Cloudflare included. Class B/C transactions are free for pay-as-you-go. Class D costs $0.004 per 10k calls, with 2,500/day free. The page footer says "© 2024" and gives no change dates — [Backblaze B2 pricing](https://www.backblaze.com/cloud-storage/pricing)
- Conflict: the niks3 wiki (Sep 2026) lists B2 at $0.006/GB, apparently the older rate. It rates performance "Good", but B2 "needs a CDN to add Content-Encoding headers" (a workaround is needed for zstd) and a CDN is required. B2 + Cloudflare costs $6/month and B2 alone $76/month in its 1 TB/10 TB scenario — [niks3 wiki](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)

**Hetzner Object Storage**
- Structure: a base price per account, billed hourly with a monthly cap, includes 1 TB storage (744 TB-hours) and about 1 TB egress per month. Unused quota does not carry over. S3 operations (PUT/GET/DELETE), ingress and internal eu-central traffic are free. Minimum billable object size is 64 kB. Limits: 750 req/s per IP per bucket, 50M objects and 100 TB per bucket, 10 Gbit/s per bucket. Locations: FSN1, HEL1, NBG1 — [Hetzner docs](https://docs.hetzner.com/storage/object-storage/overview/); [Hetzner product page](https://www.hetzner.com/storage/object-storage/)
- Price after the 2026 increase: €6.49/month base (1 TB + 1 TB egress), extra storage €8.70/TB-month, extra egress €1/TB. The source is Sliplane, a competitor, dated July 2026 — [Sliplane: Hetzner alternatives](https://sliplane.io/blog/hetzner-object-storage-alternatives); [Sliplane: cheap EU object storage](https://sliplane.io/blog/cheap-object-storage-providers-europe)
- Secondary press: Hetzner announced price increases effective 2026-04-01 across Cloud, Object Storage, Load Balancer and Dedicated, for new and existing contracts. Reported Object Storage figures vary: €4.99 → €6.49 (+30%), or €0.0081/h → €0.0104/h (+28%) — [ifun.de](https://www.ifun.de/30-prozent-aufschlag-hetzner-erhoeht-server-preise-ab-april-275083/); [winfuture.de](https://winfuture.de/news,157061.html). The pre-increase price was €4.99/month for 1 TB + 1 TB egress — [StorageNewsletter](https://www.storagenewsletter.com/?p=286311)
- Conflict: Sliplane dates the €6.49 price to July 2026, while the German press says April 2026. Neither the Hetzner product page nor the docs rendered numbers for me.
- The niks3 wiki rates Hetzner's performance "Poor" and does not recommend it: ".narinfo lookups 10s+ persist even with a CDN". The wiki's €4.99 figure is pre-increase — [niks3 wiki](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)

**AWS S3**
- GET costs $0.0004 per 1,000 (S3 Standard). The first 100 GB/month of internet egress is free, aggregated across AWS. New accounts get up to $200 in Free Tier credits (since 2025-07-15) — [AWS S3 pricing](https://aws.amazon.com/s3/pricing/)
- Storage $0.023/GB and egress $0.09/GB. CloudFront also charges $0.085/GB. Their scenario costs $923/month direct or $873 with CloudFront — [niks3 wiki](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)

**Wasabi**
- Pay-as-you-go from $7.99/TB/month, with "no charge for egress or API requests" — [Wasabi pricing](https://wasabi.com/pricing)
- Pay-as-you-go has a 1 TB minimum billed capacity and a 90-day minimum storage duration; objects deleted early incur a Timed Deleted Storage charge. Free egress holds only while monthly egress ≤ active storage (1:1) — [Wasabi pricing FAQ](https://wasabi.com/pricing/faq)
- The niks3 wiki rates performance "Good" and says a CDN is required; Cloudflare via the Bandwidth Alliance gives zero egress — [niks3 wiki](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)

**Scaleway Object Storage (Paris)**
- Standard Multi-AZ €0.01606/GB-month, One Zone €0.00803/GB-month, Glacier €0.00254/GB-month. Requests and ingress are included. Egress: 75 GB/month free, then €0.01/GB. Inter-region traffic is billed. Billing is per started GB-hour — [Scaleway storage pricing](https://www.scaleway.com/en/pricing/storage/)
- Untested by niks3. Scenario cost €114/month, mostly egress — [niks3 wiki](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)

**Tigris**
- Standard $0.02/GB-month, Infrequent Access $0.01, Archive $0.004. Class A $0.005/1,000, Class B $0.0005/1,000, DELETE free. Egress free. Free tier: the first 5 GB of Standard storage, 10,000 Class A and 100,000 Class B requests. IA has a 30-day minimum retention and Archive tiers have a 90-day minimum — [Tigris pricing](https://www.tigrisdata.com/pricing/) (fetched via raw HTML on 2026-10-12, so table mapping is approximate)

**Others (niks3 wiki, untested by its author):** OVH Standard 3-AZ costs about €14 in the 1 TB/10 TB scenario, with zero egress. Vultr, DigitalOcean and Linode each cost about $108–110, driven by egress — [niks3 wiki](https://github.com/Mic92/niks3/wiki/S3-Provider-Comparison)

### Inferences
- Monthly cost at 500 GB with under 1 TB egress (approximate): R2 $7.35; B2 about $3.50 (plus Cloudflare-proxy setup); Wasabi $7.99 (1 TB minimum); Hetzner €6.49 (but slow); Tigris about $10; Scaleway Multi-AZ about €8; AWS S3 about $11.50 for storage, plus $0.09/GB egress beyond 100 GB.
- At 50 GB: R2 $0.60, B2 about $0.28, Tigris about $0.90, Wasabi still $7.99, Hetzner still €6.49.
- Wasabi's 90-day minimum works against a GC'd cache that churns NARs. Hetzner's per-IP request limit and slow narinfo lookups hurt `nix` substitution, which issues many small HEAD/GET requests.
- The cost differences between R2, B2, Tigris and Scaleway are a few dollars a month at this scale. Operational fit (native zstd Content-Encoding, latency, no CDN glue) matters more than price, which favours R2.

### Gaps
- No primary-source 2026 confirmation of B2's per-GB rate (the page says $6.95/TB but carries a 2024 footer), or of Hetzner's exact post-increase rates (the official page did not render numbers).
- AWS S3 Standard storage and PUT prices did not render on the AWS page. The $0.023/GB figure is from the niks3 wiki.
- Scaleway and Tigris performance for Nix are untested by any source I found.

## Hosted Nix caches: Cachix, FlakeHub Cache, Garnix

### Takeaway
Cachix tiers are Starter 50 GiB, Standard 250 GiB and Pro 1500 GiB, all with unlimited bandwidth, LRU eviction and a 14-day trial. Its prices load dynamically, and I could not retrieve them. FlakeHub Cache requires a paid FlakeHub plan, and I found no public price. Garnix bundles a public and private cache with its CI: the Free plan has 1,500 CI minutes and Individual costs $25/month. Garnix caches only what Garnix builds, so it does not fit an external ephemeral builder.

### Cited Findings
- Cachix: Starter 50 GiB, Standard 250 GiB, Pro 1500 GiB, all unlimited bandwidth. 14-day free trial. Annual plans include one free month. Open-source projects get 5 GB free. Least recently used entries are removed when the limit is reached. The page shows "Please contact … for pricing" in place of the dynamic Paddle price — [Cachix pricing](https://www.cachix.org/pricing)
- Cachix has had the same tier sizes since the 2023 storage upgrade post — [Cachix blog 2023-09-12](https://blog.cachix.org/posts/2023-09-12-upgraded-storage-plans/)
- Cachix documents its own GC — [Cachix docs: garbage collection](https://docs.cachix.org/garbage-collection)
- FlakeHub Cache and private flakes are available only on paid plans. Access is limited to authenticated users granted access via org membership — [Determinate docs: FlakeHub Cache](https://docs.determinate.systems/flakehub/cache); [private flakes](https://docs.determinate.systems/flakehub/private-flakes); [Discourse announcement](https://discourse.nixos.org/t/announcing-flakehub-cache-and-private-flakes/54832)
- Garnix: Free $0 (1,500 CI minutes, public + private cache); Individual $25/month (10,000 CI minutes, cache, 1 server deployment); Enterprise custom. Extra minutes cost $0.006/min. The pricing page states no cache storage limits or retention — [Garnix pricing](https://garnix.io/pricing/)

### Inferences
- From memory and unverified: Cachix has historically been priced in the tens of euros per month for Starter. A 500 GB self-hosted R2 cache at about $7/month likely undercuts Cachix Standard (250 GiB).
- FlakeHub Cache and Garnix both tie the cache to their own build or publish pipeline. They suit "CI builds everything" better than "my own ephemeral builder pushes".

### Gaps
- Cachix euro prices (rendered via a Paddle API on page load), FlakeHub pricing (determinate.systems/pricing returned 404), and Garnix cache size and retention limits were all unavailable.

## Cache server software: attic, niks3, harmonia, nix-serve-ng, ncps, plain `nix copy`; GC on static S3 caches

### Takeaway
For "ephemeral builder → object storage → all machines read directly", the best current fit is niks3. It is very active (v1.15.0 released 2026-10-12) and adds reference-tracking GC to a plain static S3 cache, which stays readable by stock Nix. Attic adds chunk-level dedup and server-side signing, but requires its server in the read path, and it still calls itself "an early prototype". harmonia and nix-serve-ng serve a live `/nix/store`, which conflicts with an ephemeral builder. ncps is a pull-through proxy, not a push target. Plain `nix copy` to S3 works but has no safe GC; lifecycle rules can delete NARs and leave narinfos pointing at 404s.

### Cited Findings
**Project status (GitHub API, 2026-10-12)**
- attic: 2,116 stars, not archived, last push 2026-10-01. Recent commits are the June–July 2026 SeaORM 2.0 migration and native async-fn-in-trait refactors. It has no GitHub releases — [zhaofengli/attic](https://github.com/zhaofengli/attic)
- niks3: 305 stars, v1.15.0 released 2026-10-12, v1.14.2 released 2026-10-07 — [Mic92/niks3](https://github.com/Mic92/niks3)
- harmonia: 626 stars, harmonia-v3.3.0 released 2026-09-18 — [nix-community/harmonia](https://github.com/nix-community/harmonia)
- nix-serve-ng: 230 stars, last push 2026-04-30 — [aristanetworks/nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng)
- ncps: 345 stars, still on release candidates (v0.10.0-rc17, 2026-09-07) — [kalbasit/ncps](https://github.com/kalbasit/ncps)

**attic**
- Self-hostable, S3-backed, multi-tenant. Has global dedup, managed signing ("the user pushing store paths does not have access to the signing key") and LRU GC. Calls itself "an early prototype" — [attic README](https://github.com/zhaofengli/attic)
- Config: an R2 endpoint example, content-defined chunking for NARs ≥ 64 KiB (`nar-size-threshold = 65536`), GC `interval = "12 hours"` and an optional `default-retention-period` (e.g. "6 months") — [config-template.toml](https://raw.githubusercontent.com/zhaofengli/attic/main/server/src/config-template.toml)
- The NixOS deployment guide lists MinIO, Backblaze B2 and Cloudflare R2 as storage options — [attic NixOS deployment docs](https://raw.githubusercontent.com/zhaofengli/attic/main/book/src/admin-guide/deployment/nixos.md)
- GC is layered: collecting an object removes only the cache → NAR mapping. Storage is freed only after orphan NARs and then orphan chunks are removed — via [Attic introduction, Discourse](https://discourse.nixos.org/t/introducing-attic-a-self-hostable-nix-binary-cache-server/24343/1)

**niks3**
- Write path: the CLI asks the server for presigned S3 URLs, uploads NAR + narinfo directly to S3, and the server tracks references in PostgreSQL. Read path: Nix clients read S3 (or a CDN) directly, not via niks3. The GC server can be a single instance next to CI, since writes are less critical than reads — [niks3 README](https://github.com/Mic92/niks3)
- Features: Ed25519 signing compatible with `nix key generate-secret`, zstd NARs, build logs, CA realisations, multipart, transactional closure uploads with rollback, reference-tracking GC with configurable retention, and a parallel and streaming push — [niks3 README](https://github.com/Mic92/niks3)
- Ops: Bearer API tokens, OIDC for GitHub Actions and GitLab CI, auto-upload via post-build-hook with a crash-safe SQLite queue, Prometheus metrics, a Helm chart. Recommends Cloudflare R2. Deployed by Clan infra, Numtide and TUM-DSE — [niks3 README](https://github.com/Mic92/niks3)

**harmonia**
- Serves the local `/nix/store` as a binary cache over HTTP, with http-range support and transparent zstd. Signing keys are configured via `services.harmonia.cache.signKeyPaths`, and the README shows a sops-nix example — [harmonia README](https://github.com/nix-community/harmonia)

**nix-serve-ng**
- A faster, more reliable drop-in replacement for nix-serve, focused on backward compatibility; it mentions Lix compatibility — [nix-serve-ng README](https://github.com/aristanetworks/nix-serve-ng)

**ncps**
- A pull-through proxy for upstream caches (e.g. cache.nixos.org) with multi-upstream failover. Storage on the local filesystem or S3; SQLite, PostgreSQL or MySQL; LRU size limits; signs cached paths with its own key. HA needs S3 + Postgres/MySQL + Redis and CDC enabled — [ncps README](https://github.com/kalbasit/ncps)

**GC on static S3 caches and lifecycle-rule risk**
- The Nix S3 store supports `storage-class` (e.g. STANDARD_IA, GLACIER_IR) but has no GC of its own — [Nix manual](https://nix.dev/manual/nix/latest/store/types/s3-binary-cache-store)
- Nix PR #8080 proposed expiring debug NARs via S3 lifecycle rules, because deleting narinfos one by one is slow and costly. Moving NARs to another prefix would "break the format of binary caches", so the PR tagged objects at upload time instead — [NixOS/nix#8080](https://github.com/NixOS/nix/pull/8080)
- The cache.nixos.org GC effort enabled bucket versioning plus a lifecycle rule deleting non-current versions after 30 days. Deleted objects return 404 but stay restorable for 30 days — [Discourse: garbage collecting cache.nixos.org](https://discourse.nixos.org/t/garbage-collecting-cache-nixos-org/74249/10)

### Inferences
- Lifecycle failure modes on a static cache: (1) An age-based rule on `nar/` expires a NAR whose narinfo survives. Clients see the path as available, fetch the NAR, get a 404 and fail substitution; Nix may fall back to building, or error with `--option fallback false`. (2) Expiring narinfos but not their references breaks closures: a surviving narinfo whose referenced paths were deleted is unusable. (3) Age-based rules ignore use: a NAR uploaded long ago but still referenced by today's system closure gets deleted. Also, NARs are content-addressed by file hash and can be shared by several narinfos. Reference- or root-aware GC (niks3, attic, Cachix) avoids all three. The safest lifecycle rule for a static cache is "abort incomplete multipart uploads after N days".
- Dedup: plain S3 caches dedup only identical NAR files. attic's chunking dedups across similar NARs (e.g. successive versions of a large package), which matters most for frequently rebuilt big closures. At 50–500 GB that saves cents to a few dollars a month on R2, so it is not decisive.
- The ephemeral builder fits niks3 + R2 well. The builder authenticates to niks3 with a token, or OIDC from CI, and never holds S3 credentials. Readers hit R2 directly, so the niks3 server can be down without breaking substitution. One cost: niks3 needs PostgreSQL, though it can be small.

### Gaps
- I found no published benchmark of attic vs niks3 on R2. I did not verify whether niks3 GC deletes a narinfo before its NAR (the ordering matters for concurrent readers), or how attic behaves on R2 under its chunk GC.
- Attic's release cadence: no tags exist, so "stability" depends on the commit history.

## Signing key handling and security for self-hosted caches

### Takeaway
Nix trusts only narinfos signed by a key listed in `trusted-public-keys`, so the signing key is the security boundary, not bucket access. Keep the key off the ephemeral builder where possible. Attic signs on the server, so pushers never hold the key. With niks3 or `nix copy`, the key signs at push time. Keep secrets in sops-nix/agenix, use scoped push credentials (niks3 tokens/OIDC, S3 keys limited to one bucket) and make reads public or token-gated.

### Cited Findings
- Attic "Managed Signing: signing is done on-the-fly by the server when store paths are fetched. The user pushing store paths does not have access to the signing key." — [attic README](https://github.com/zhaofengli/attic)
- niks3 signs NARs with Ed25519 keys compatible with `nix key generate-secret`. It authenticates pushers via Bearer API tokens or OIDC (GitHub Actions, GitLab CI), so CI needs no long-lived secret. Uploads go to presigned S3 URLs, so clients never receive S3 credentials. Presigned read-redirect URLs are bearer capabilities until they expire — [niks3 README](https://github.com/Mic92/niks3)
- The harmonia README generates keys with `nix-store --generate-binary-cache-key cache.yourdomain.tld-1 …` and shows storing the secret via sops-nix (`config.sops.secrets.harmonia-key.path`). Clients pin it in `trusted-public-keys` — [harmonia README](https://github.com/nix-community/harmonia)
- Nix S3 store: the `secret-key`/`secret-keys` settings sign on upload. Uploads need IAM `s3:PutObject`, `s3:ListBucket` and `s3:AbortMultipartUpload`; authenticated reads need `s3:GetObject`, `s3:GetBucketLocation` and `s3:ListBucket` — [Nix manual](https://nix.dev/manual/nix/latest/store/types/s3-binary-cache-store)
- R2 access control via Access/WAF token auth only works if r2.dev is disabled — [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- ncps re-signs proxied paths with its own private key — [ncps README](https://github.com/kalbasit/ncps)

### Inferences
- Threat model: if someone gets the signing key, every machine that trusts it will accept their malicious paths, including root-level NixOS system closures. If someone gets only bucket write access without the key, they can delete or corrupt objects, which is a denial of service. Clients reject unsigned or wrongly signed narinfos, though NAR hash checks still depend on the narinfo.
- Practical rules: one key per cache, named `cache.example-1` so it can rotate (add a new key name, then retire the old one in `trusted-public-keys`). Keep the key in sops-nix/agenix and inject it into the ephemeral builder only for the push step, or prefer server-side signing (attic). Scope the S3/R2 API token to one bucket with write but not delete if the GC runs elsewhere. Do not set `require-sigs = false`. Do not add users to `trusted-users` just to let them push.
- An unsigned post-build-hook that pushes every build also pushes builds from untrusted inputs. Only push from builds you control.
- Private caches: Nix supports netrc basic auth for HTTP substituters, which pairs naturally with a Worker or niks3 read proxy. The netrc file must be readable by the nix-daemon.

### Gaps
- No authoritative 2026 Nix security guidance on key rotation or on HSM/remote-signing support in Nix itself. These recommendations are inference from tool designs.
