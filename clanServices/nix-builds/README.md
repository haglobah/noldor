# nix-builds

Repos that install Beat's GitHub App and declare `buildJobs.<system>` in
their flake get those outputs built, signed, and pushed to a private
Cloudflare R2 binary cache. The build machine, aule, is a Hetzner Cloud
server that only exists while there is something to build. Hetzner bills
every started hour while a server exists, even when it is powered off.

Design and decisions: `docs/nix-builds-plan.md`.

## How a commit gets built

1. GitHub sends a `push` webhook to `https://<domain>/webhook` on the
   scheduler (orthanc). A poll every `pollInterval` seconds (default 300)
   catches missed webhooks.
2. The scheduler queues the commit if it is on the default branch or a tag
   matching `tagPattern` (default `v*`). One job per ref: a newer commit
   replaces a queued one. One job runs at a time.
3. It evaluates `buildJobs.x86_64-linux` of that commit (GitHub tarball,
   App installation token) and asks R2 for every output.
4. All outputs cached (for example because gondor pushed them): done,
   green commit status. aule stays off.
5. Otherwise it starts aule from its newest snapshot (CX53, then CCX33;
   fsn1, then nbg1), copies the derivations over `ssh-ng`, and builds them
   there. aule fetches sources and dependencies itself.
6. aule's post-build hook signs every output with aule's key and pushes it
   to R2. The scheduler waits until R2 has all outputs, then sets the
   commit status.
7. aule deletes itself after 10 minutes without builds, late in a billed
   hour (minute 50 or later). It always deletes itself after 6 hours.

Results:

| Result  | Meaning                                                         | Commit status | Retried               |
| ------- | --------------------------------------------------------------- | ------------- | --------------------- |
| success | every output is in R2                                           | success       | no                    |
| skipped | no `buildJobs.x86_64-linux`                                     | none          | no                    |
| failure | evaluation or build failed, or outputs never reached R2         | failure       | no (`nix-builds retry`) |
| error   | aule did not start, vanished mid-build, or R2 lookups failed    | error         | every poll            |

A failure posts to ntfy. An error posts once per commit while it retries.

## Roles

| Role        | Machines | What it does                                                                                   |
| ----------- | -------- | ---------------------------------------------------------------------------------------------- |
| `client`    | all      | Substitutes from R2 after cache.nixos.org; trusts aule's and gondor's keys.                    |
| `pusher`    | gondor   | Signs everything it builds with gondor's own key and pushes it.                                |
| `builder`   | aule     | Builds for the scheduler as the untrusted `nix-ssh` user; signs and pushes with aule's key; reaps itself. |
| `scheduler` | orthanc  | The daemon: webhook, poll, queue, cache checks, starting aule, commit statuses.                |

## Who holds what

| Secret                           | Where                     | Why                                     |
| -------------------------------- | ------------------------- | --------------------------------------- |
| R2 read token                    | every machine (nix-daemon), the scheduler | substitute, check the cache |
| R2 write token                   | gondor, aule              | push                                    |
| gondor's signing key             | gondor                    | sign its own builds                     |
| aule's signing key               | aule                      | sign builds for the scheduler           |
| GitHub App private key, webhook secret | orthanc             | installation tokens, verify webhooks    |
| Hetzner token                    | orthanc, aule, gondor     | create; self-delete; refresh the snapshot |
| SSH key for `nix-ssh@aule`       | orthanc                   | send derivations to aule                |

orthanc can make aule build any derivation, but as an untrusted Nix user
it cannot import unsigned paths into aule's store, so it cannot get
arbitrary paths signed.

## Registering a repo

1. Install the GitHub App on the repo (GitHub → Settings → Applications →
   the App → Configure → Repository access).
2. Add `buildJobs.<system>` to the flake: a flat attribute set of
   derivations, like `hydraJobs` without nesting.

   ```nix
   flake.buildJobs.x86_64-linux = {
     inherit (self.packages.x86_64-linux) frontend backend;
   };
   ```

noldor does not change when a repo adds, removes or changes outputs.

## One-time setup

1. **Cloudflare R2:** create the bucket `nix-cache`, a read-only token
   and a read-write token, both scoped to that bucket (R2 → Manage API
   tokens).
2. **Hetzner:** create a project token with Read & Write.
3. **GitHub App** (Settings → Developer settings → GitHub Apps → New):
   - Homepage: anything. Webhook URL: `https://builds.hagenlocher.me/webhook`.
     Webhook secret: from step 4, so fill it in afterwards.
   - Repository permissions: Contents read, Metadata read, Commit statuses
     read & write.
   - Subscribe to events: Push. (Installation events arrive without
     subscribing.)
   - Only on this account. Create it, note the App ID, generate a private
     key (.pem).
4. **Vars**, entered at the prompts:
   ```
   clan vars generate gondor   # R2 account id and tokens, Hetzner token, gondor's key
   clan vars generate aule     # host key, aule's signing key
   clan vars generate orthanc  # GitHub App ID and .pem, webhook secret, scheduler SSH key
   clan vars get orthanc nix-builds-github/webhook-secret   # paste into the App
   ```
5. **aule's snapshot:** see `docs/nix-builder.md` ("Bootstrap"). After
   config changes to aule: `just builder-snapshot`.
6. Deploy gondor, then `just deploy-formenos` and `just deploy-orthanc`.
7. Install the App on the repos to build.

## Operating it

On orthanc:

```
sudo -u nix-builds nix-builds status             # queue and recent results
sudo -u nix-builds nix-builds retry OWNER/REPO SHA   # forget a result; the next poll rebuilds a head
journalctl -u nix-builds -f
```

On gondor: `just builder-status`, `just builder-down`.

## Known limits

- The bucket only grows; there is no garbage collection yet.
- If the Hetzner token is revoked or the API is down, aule cannot delete
  itself and keeps billing (up to and beyond its 6-hour cap).
- aule's reaper counts a running upload as busy, but not a queued upload
  that failed. If the push fails, aule may delete itself with outputs
  unpushed; the scheduler then reports a failure for that commit.
- Only `x86_64-linux`.
