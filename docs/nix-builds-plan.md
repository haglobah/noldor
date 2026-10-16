# Plan: the `nix-builds` clan service

Status: implemented, not deployed, 2026-10-14. Replaces the manual `just builder-up` path and
ht's `release-cache.yml` workflow from the first iteration.

## Goal

When a registered repo gets a new commit, its declared outputs end up signed
in the R2 cache, without anyone waking a builder. orthanc notices the commit,
checks the cache, and only if something is missing, it starts aule and
builds there. gondor never has to wake aule.

## Decisions (Beat, 2026-10-13)

- Trigger: GitHub webhook, plus a slow poll (every 5 min) as backup.
- Repo access and registration: one private GitHub App. Installing it on a
  repo registers the repo. Permissions: Contents read, Metadata read,
  Commit statuses write (optional, see open questions). It also sends the
  webhooks.
- aule signs and pushes. Its own signing key and the R2 write token live in
  aule's clan vars.
- Custom service, not buildbot-nix. Written in Python (stdlib only, plus
  `openssl` for the App's RS256 JWT), not shell.
- Each repo declares what to build in its own flake, so noldor does not
  change when a repo's outputs change.

Why Python over Janet: the scheduler needs HTTPS requests, JSON, HMAC
checks, RS256 signing, SQLite and subprocesses. Python's stdlib covers all
but RS256. Janet would need spork plus shelling out to curl and openssl for
most of it. Janet works, with more glue and fewer tests ready to hand.

## The repo contract

A repo opts in by:

1. Installing the GitHub App on it.
2. Exposing `buildJobs.<system>` in its flake: an attribute set of
   derivations, like `hydraJobs`. Example for ht:

   ```nix
   flake.buildJobs.x86_64-linux = {
     inherit (self.packages.x86_64-linux)
       frontend-deploy frontend-deploy-dev backend mail-frontend mail-backend;
   };
   ```

Built refs: the default branch and tags matching `v*`. A commit without
`buildJobs` is skipped and logged, not treated as an error.

## Components

### Role `scheduler` (orthanc)

Python daemon `nix-builds-scheduler`, one systemd service with state in
`/var/lib/nix-builds` (SQLite).

- **Webhook:** Caddy vhost (domain: open question) → loopback port. Rejects
  requests without a valid `X-Hub-Signature-256`. Handles `push` (branch and
  tag) and `installation_repositories` (repo added or removed).
- **Poll:** every 5 min, list the App's installed repos and their default
  branch and `v*` tag heads. Catches missed webhooks.
- **Queue:** one job per (repo, ref). A newer commit on the same ref replaces
  a queued one. One job runs at a time.
- **Job:**
  1. Fetch the commit over HTTPS with an installation token (short-lived).
  2. `nix eval` `buildJobs.x86_64-linux` → drv and out paths, inside the
     existing capped `updaters.slice`.
  3. Ask R2 for each out path's `.narinfo`. All present → done.
  4. Otherwise, start aule if it is down (Hetzner API, CX53 then CCX33,
     newest snapshot), and wait for SSH.
  5. `nix copy --derivation --to ssh-ng://aule` and
     `nix build --store ssh-ng://aule '<drv>^*'`. aule fetches its own
     sources and dependencies. orthanc needs no build space.
  6. Check that R2 now has every out path. Record the result.
- **Failures** are explicit: a failed job is logged, recorded in SQLite and
  posted to the existing ntfy topic. A Hetzner or GitHub API error retries
  with backoff and never fails silently.
- Holds: GitHub App private key and webhook secret, Hetzner token, SSH key
  for aule, R2 read token. Nothing that can sign.

### Role `builder` (aule)

What exists now, moved into the service:

- The reaper: idle for 10 min and near the end of the paid hour → delete
  itself; hard cap 6 h.
- New: the post-build hook and push queue (moved from gondor), signing with
  aule's own key.
- orthanc connects as an **untrusted** Nix user (`nix-ssh`). It can have
  derivations built but cannot import unsigned paths, so a compromised
  orthanc cannot get arbitrary paths signed. This needs a test; if Nix
  refuses the build for untrusted users, I come back to you first.

### Role `client` (all machines)

Substitute from R2 and trust aule's public key. (Superseded: gondor
first kept its own push hook and key; see decision 4.)

## Changes per repo

| Repo        | Change                                                                          |
| ----------- | ------------------------------------------------------------------------------- |
| noldor      | `clanServices/nix-builds/`; current `nix-cache*` and `nix-builder*` modules move into its roles; `builder-up` recipes go (keep `builder-status` and `builder-down`). |
| ht          | Add `buildJobs`; delete `release-cache.yml`. The substitute-only updater stays. |
| media-inbox | Add `buildJobs` (worker).                                                       |
| notable     | Add `buildJobs` (sync server).                                                  |

## Tests (red/green)

- Python unit tests, as a flake check: webhook signature check, push and
  installation event parsing, ref filtering, queue coalescing, the cache
  decision (all cached → no wake), the start decision, the JWT format. Fake
  GitHub, Hetzner and nix through injected functions.
- Module eval tests: roles wire units, vars and Caddy as expected.
- Untrusted `ssh-ng` build: a small NixOS VM test with two nodes, if it
  stays affordable; otherwise a manual check, recorded as such.

## Answered questions

1. Webhook domain: `builds.hagenlocher.me`.
2. Commit statuses: yes. The App gets Commit statuses write; the scheduler
   posts pending, success and failure per commit (context `nix-builds`).
3. gondor does not use aule. It builds locally or downloads.
4. gondor does not push (2026-10-15). Only aule writes to the bucket and
   only aule's key is trusted. gondor's `pusher` role, its signing key and
   `just cache-push` are gone; `just cache-check` uses the read token.
5. Secrets one machine needs are per-machine vars (2026-10-15): aule's
   signing key on aule, the scheduler's SSH key on orthanc. Others read
   the public halves from `vars/per-machine/`. Shared generators with a
   per-machine `deploy` failed `clan vars generate` ("different
   definitions for shared generator"), and clan encrypts shared secrets
   for every machine that declares them.

## Out of scope, recorded

- GC for the bucket (niks3 later).
- orthanc's updater key: once the App exists, the updaters could clone with
  App tokens too and the account-level SSH key could go.
- ht's `ci.yml` and `todos-deploy.yml` still use magic-nix-cache.

## Implementation notes (2026-10-14)

Verified:

- 66 scheduler unit tests (run in the package's checkPhase,
  `checks.nix-builds-scheduler`). The `ops` tests were written together
  with the code and never seen red.
- `checks.nix-builds-untrusted` (two-node VM): an untrusted `ssh-ng` user
  copies derivations and builds them on the builder; importing an unsigned
  output fails with "lacks a signature by a trusted key".
- `checks.nix-builder-reaper`.
- orthanc, formenos, gondor evaluate; with stub public vars, aule too.
- ht, media-inbox and notable expose `buildJobs.x86_64-linux`; the
  scheduler's eval expression returns their drvs and outputs.

Not verified against the real services: GitHub App API calls, webhook
delivery, Hetzner's capacity error codes (`CAPACITY_CODES` in
`hetzner.py` is a guess), the private-repo tarball fetch with an
installation token, a real flake build through `ssh-ng` as untrusted user.

Open:

- noldor pins `notable` and `media-inbox` with `inputs.nixpkgs.follows =
  "nixpkgs"`, so what noldor deploys is a different derivation than the
  repo's `buildJobs` and never hits the cache. ht has no follows and
  matches.
- aule's reaper does not count a failed, still-queued upload as busy.
- gondor's running system still lists aule as a remote builder (from the
  first iteration); the next gondor switch removes it.

