# Private Nix binary cache on Cloudflare R2

## What it is

A Cloudflare R2 bucket, `nix-cache`, that holds Nix store paths built in
this clan. It is private: every request is signed with an R2 API token.

- **All machines** read it as an extra substituter, after
  `cache.nixos.org` (priority 50 vs. 40). They only accept paths signed
  with the clan's cache key (`noldor-nix-cache-1`). See
  `modules/nix-cache.nix`, imported for every machine via the `common`
  instance in `clan.nix`.
- **gondor** pushes. Every derivation it builds, locally or on a remote
  builder, is queued by a `post-build-hook` and uploaded, signed, by
  `nix-cache-push.service`. `just cache-push` pushes a whole closure on
  demand. See `modules/nix-cache-push.nix`.

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
| `nix-cache-write`       | read-write token, profile `nix-cache-write` | gondor                |
| `nix-cache-signing-key` | `public-key` public, `secret-key` secret    | public: all; secret: gondor |

All four are shared clan vars. nix-daemon gets
`AWS_SHARED_CREDENTIALS_FILE=/run/secrets/vars/nix-cache-read/credentials`.
The push side (`nix-cache` script, run as root) points the same variable
at the write token. The `profile=` in each URL picks the matching section.

Until `nix-cache-account` and `nix-cache-signing-key` are generated, the
machines evaluate without the cache and print a `nix-cache:` warning.

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
`nix-cache-push.service`, which uploads each entry with `--no-recursive`
(only the outputs: their dependencies were substituted, so a cache has
them, or built here and queued on their own). A failed upload stays queued,
fails the unit (visible in `systemctl --failed`), and the timer retries
every 15 min.

Everything gondor builds ends up in the bucket, including store paths that
carry secrets. The bucket is private, but every machine's read token can
read all of it.

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
   bucket `nix-cache` only.

### 2. Clan vars

Type the values in when prompted:

```sh
clan vars generate gondor -g nix-cache-account      # Account ID
clan vars generate gondor -g nix-cache-signing-key  # no prompt
clan vars generate gondor -g nix-cache-read         # read-only key id + secret
clan vars generate gondor -g nix-cache-write        # read-write key id + secret
clan vars generate orthanc
clan vars generate formenos
```

The last two only add orthanc and formenos as recipients of the shared
vars (nothing to type for the cache). `clan vars check <machine>` confirms.
Commit the new files under `vars/shared/nix-cache-*`.

### 3. Deploy

Deploy gondor first and push something (below). The first push writes
`nix-cache-info`; until it exists, readers warn that they cannot open the
cache. Then deploy orthanc and formenos.

## Push and verify

On gondor (the `nix-cache` script needs root for the write token):

```sh
just cache-push .#nixosConfigurations.orthanc.config.system.build.toplevel
just cache-check nixpkgs#hello           # path-info --sigs from R2
sudo nix-cache push --no-recursive /nix/store/...-foo   # outputs only
sudo nix-cache info /nix/store/...-foo
```

`cache-push` uploads the whole closure, including paths `cache.nixos.org`
already has. That costs storage; prefer `--no-recursive` for single paths.

Queue state:

```sh
sudo ls /var/lib/nix-cache-push/queue
systemctl status nix-cache-push.service
journalctl -u nix-cache-push.service
```

Raw check from any machine, with the read token:

```sh
sudo env AWS_SHARED_CREDENTIALS_FILE=/run/secrets/vars/nix-cache-read/credentials \
  nix path-info --sigs \
  --store 's3://nix-cache?endpoint=https://<ACCOUNT_ID>.r2.cloudflarestorage.com&region=auto&profile=nix-cache-read' \
  /nix/store/...-foo
```

The output must list a `noldor-nix-cache-1:` signature.

End to end:

```sh
# gondor: build something unique; the hook queues and uploads it
nix build --print-out-paths --impure --expr \
  "(import <nixpkgs> {}).runCommand \"r2-test-$(date +%s)\" {} \"echo hi > \$out\""
# orthanc or formenos: fetch it through nix-daemon's substituters
nix-store -r /nix/store/...-r2-test-...
```

`nix-store -r` must report `copying path ... from 's3://nix-cache?...'`.

## Not covered here

- Garbage collection in the bucket. Nothing deletes old paths yet; an R2
  object lifecycle rule (delete after N days) is the simple option.
- The build machine aule (docs/nix-builder.md) does not push and holds no
  write token or signing key: gondor's hook pushes its outputs once they
  are copied back.
