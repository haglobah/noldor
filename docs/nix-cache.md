# Private Nix binary cache on Cloudflare R2

## What it is

A Cloudflare R2 bucket, `nix-cache`, that holds Nix store paths built in
this clan. It is private: every request is signed with an R2 API token.

It is part of the nix-builds clan service
(`clanServices/nix-builds/README.md`).

- **All machines** (role `client`, `client.nix`) read it as an extra
  substituter, after `cache.nixos.org` (priority 50 vs. 40). They accept
  paths signed by aule's key (`noldor-aule-1`).
- **Only aule** (role `builder`) pushes. Every derivation it builds is
  queued by a `post-build-hook` and uploaded, signed, by
  `nix-cache-push.service` (`push.nix`). gondor and the servers never
  write to the bucket.

Store URL (`<ACCOUNT_ID>` is the Cloudflare account ID):

```
s3://nix-cache?endpoint=https://<ACCOUNT_ID>.r2.cloudflarestorage.com&region=auto
```

- `region=auto` is what R2 expects in the SigV4 signature.
- A full `endpoint` URL makes Nix use path-style addressing
  (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com/nix-cache/...`).
- Readers add `&profile=nix-cache-read&priority=50`.
- Pushes add `&profile=nix-cache-write&secret-key=...&compression=zstd&parallel-compression=true&multipart-upload=true`.
  zstd compresses and decompresses much faster than the xz default.
  Multipart lifts the 5 GiB single-upload limit.

### Credentials

Nix (2.33+, here 2.34) signs S3 requests itself and finds credentials
through the AWS default chain: environment, SSO, profile file, ... It does
not read them from `nix.conf`. So:

| var generator           | content                                | deployed to                |
| ----------------------- | -------------------------------------- | -------------------------- |
| `nix-cache-account`     | account ID, public                     | all (read at eval time)    |
| `nix-cache-read`        | read-only token, profile `nix-cache-read`   | all                   |
| `nix-cache-write`       | read-write token, profile `nix-cache-write` | aule                  |
| `nix-builds-builder-key` | aule's key: `public-key` public, `secret-key` secret | public: all; secret: aule |

The account ID and the two tokens are shared clan vars (`vars.nix`).
aule's key is a per-machine var on aule (`push.nix`); the other machines
read its public half from `vars/per-machine/aule/`. clan wants a shared
generator declared alike on every machine and encrypts its secrets for
all of them, so a secret only one machine needs is never shared.
nix-daemon gets
`AWS_SHARED_CREDENTIALS_FILE=/run/secrets/vars/nix-cache-read/credentials`.
aule's push side (`nix-cache` script, run as root) points the same
variable at the write token. `nix-cache-info` (all machines, root) uses
the read token. The `profile=` in each URL picks the matching section.

Until the account ID and aule's public key are generated, the machines
evaluate without the cache and print a `nix-builds:` warning.

### When R2 is down or unreachable

`fallback = true`: a failed R2 lookup does not fail the build. Nix builds
locally and skips R2 for 60 s. `connect-timeout = 5`. Signatures are always
required (`require-sigs` stays at its default `true`). Note that `fallback`
also applies to `cache.nixos.org`: if it is down, Nix builds from source.

A missing path costs nothing: R2 answers 404, Nix tries the next cache.
Nix caches "not found" for an hour (`narinfo-cache-negative-ttl`), so a
machine that looked for a path before it was pushed may not see it for up
to an hour.

### The post-build hook

Facts from the Nix 2.34 source (`src/libstore/build/derivation-building-goal.cc`):

- The hook runs after local builds (`buildLocally`) **and** after builds on
  a remote builder (`buildWithHook`, i.e. `builders = ...`), on the machine
  that dispatched the build, once the outputs are copied back.
- It runs inside nix-daemon as root, synchronously: it blocks the build
  loop. If it fails, the build succeeds but no further builds run.

So the hook only writes the output paths into
`/var/lib/nix-cache-push/queue/` and always exits 0. A path unit starts
`nix-cache-push.service`, which uploads each entry with its closure. A
binary cache only accepts a path whose references it already holds, and
dependencies that aule substituted from cache.nixos.org or got as copied
sources are never queued. `nix copy` skips what R2 already has, so the
upstream part of a closure is uploaded once. A failed upload stays queued,
fails the unit (visible in `systemctl --failed`), and the timer retries
every 15 min.

Everything aule builds ends up in the bucket. aule only builds the
`buildJobs` of registered repos, so keep secrets out of those outputs. The
bucket is private, but every machine's read token can read all of it.

## Setup (one time)

### 1. Bucket and tokens in the Cloudflare dashboard

1. Cloudflare dashboard → **R2 Object Storage** → **Create bucket**.
   Name `nix-cache`, location *Automatic*, storage class *Standard*.
   Leave public access (r2.dev / custom domain) **off**.
2. Note the **Account ID**: R2 Object Storage → Overview → *Account
   Details* (right column). It is also in the S3 API URL
   `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`.
3. R2 Object Storage → Overview → *Account Details* → **Manage API
   tokens** (`{ } Manage` next to *API Tokens*) → **Create Account API
   token**:
   - Name `nix-cache-read`, permission **Object Read only**,
     *Specify bucket(s)* → *Apply to specific buckets only* → `nix-cache`,
     TTL *Forever*. Create.
   - Copy **Access Key ID** and **Secret Access Key**. The secret is shown
     only once. (The "Token value" is not needed.)
4. Same again: name `nix-cache-write`, permission **Object Read & Write**,
   bucket `nix-cache` only. Only aule gets this one.

### 2. Clan vars and deploy

See the setup steps in `clanServices/nix-builds/README.md`. The vars are
generated with `clan vars generate aule`, which prompts for the account
ID and both tokens. Commit the new files under `vars/`.

aule's first push writes `nix-cache-info`; until it exists, readers warn
that they cannot open the cache.

## Verify

From any machine, with the read token:

```sh
just cache-check nixpkgs#hello           # gondor: evaluates, then nix-cache-info
sudo nix-cache-info /nix/store/...-foo   # path-info --sigs from R2
```

A cached path lists a `noldor-aule-1:` signature. A missing one reports
that the path is not valid in the store.

aule's upload queue, while aule exists:

```sh
ssh root@aule ls /var/lib/nix-cache-push/queue
ssh root@aule journalctl -u nix-cache-push.service
```

## Not covered here

- Garbage collection in the bucket. Nothing deletes old paths yet. Do not
  use an R2 lifecycle rule that deletes by age: it can delete a NAR while
  its `.narinfo` stays, and machines then fail to fetch a path the cache
  claims to have. niks3 (Mic92) tracks references for a safe GC.
