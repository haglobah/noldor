# On-demand build machine `aule`

## What it is

`aule` is a Hetzner Cloud server that exists only while gondor needs build
power. gondor's nix-daemon sends builds to it over `ssh-ng`. When it does
not exist, Nix builds on gondor as before.

- **Created** from the newest snapshot labelled `machine=aule` by
  `just builder-up`. It tries CX53 (16 shared vCPU, 32 GB) in fsn1, then
  nbg1, then CCX33 (8 dedicated vCPU, 32 GB) in fsn1, then nbg1.
- **Deleted** by itself when idle (below), or by `just builder-down`.
  Hetzner bills every started hour while a server exists, even powered
  off, so "off" means deleted.
- **No cache credentials.** aule reads the R2 cache like every machine
  (read-only token, `modules/nix-cache.nix`) but never pushes. gondor's
  post-build hook also fires for remote builds once the outputs are copied
  back, so gondor signs and pushes what aule built (docs/nix-cache.md).

Files:

| file                              | what                                                    |
| --------------------------------- | ------------------------------------------------------- |
| `machines/aule/`                  | disko layout (`/dev/sda`), qemu-guest hardware, growpart |
| `modules/nix-builder.nix`         | aule: `nix-ssh` user, nix settings, self-deletion timer  |
| `modules/nix-builder-client.nix`  | gondor: build machine, ssh alias, `nix-builder` CLI      |
| `modules/nix-builder-vars.nix`    | shared vars: `hcloud-token`, `nix-builder-ssh`          |
| `modules/nix-builder/`            | CLI script and the self-deletion decision               |
| `tests/nix-builder-reaper.nix`    | unit test of that decision (`checks.nix-builder-reaper`) |

## Costs

| item                   | price                       | source                                   |
| ---------------------- | --------------------------- | ---------------------------------------- |
| CX53, 16 vCPU / 32 GB  | ~€0.0473 per started hour   | Hetzner, as of 2026; `builder-up` prints the live gross price |
| CCX33, 8 vCPU / 32 GB  | ~€0.2219 per started hour   | same                                     |
| snapshot storage       | ~$0.0143 per GB-month (net) | **unverified**: third-party price lists, not Hetzner's page |

A snapshot of a NixOS system holds a few GB, so storage is cents per month.
The 6 h cap limits a forgotten server to 6 started hours: ~€0.28 on CX53,
~€1.33 on CCX33.

## How gondor reaches it

- `nix.buildMachines`: `ssh-ng://nix-ssh@aule`, 4 jobs, features
  `big-parallel` and `benchmark` (no `kvm`: Hetzner's VMs have no nested
  virtualisation, so NixOS VM tests stay on gondor).
- `builders-use-substitutes = true`: aule fetches inputs from
  cache.nixos.org and R2 itself instead of over gondor's uplink.
- **Address.** Every server gets a new IP. `/etc/ssh/ssh_config` includes
  `/var/lib/nix-builder/ssh_config`, which `nix-builder up` writes as
  `Host aule / HostName <ip>`. Without that file, the fallback
  `HostName aule.invalid` fails to resolve at once, so Nix builds locally
  without waiting. `ConnectTimeout 5`.
- **Host key.** aule's host key is its clan var `openssh`, restored with
  every snapshot. gondor pins it in `/etc/ssh/ssh_known_hosts` under
  `aule`; `HostKeyAlias aule` makes ssh look it up there despite the
  changing IP.
- **Login.** nix-daemon (root) uses the shared var `nix-builder-ssh`
  (private key deployed to gondor only). On aule it may log in as
  `nix-ssh` only, whose ForceCommand is `nix-daemon --stdio`
  (`nix.sshServe`). `nix-ssh` is a trusted user: remote builds of
  unsigned derivations need that, and it amounts to root over the store.
- **Stale address.** aule does not tell gondor when it deletes itself.
  `nix-builder-sync.timer` on gondor asks the Hetzner API every minute
  while an address is recorded and removes the file once aule is gone.
- `clan machines update aule` works through the same alias
  (inventory `deploy.targetHost = "root@aule"`).

Nix tries a free remote slot before building locally. If ssh fails, Nix
logs `cannot build on 'ssh-ng://nix-ssh@aule'` and builds locally. If all
4 remote slots are busy, it also builds locally. Force one side:

```sh
nix build --builders '' ...    # local only
nix build --max-jobs 0 ...     # remote only
```

## Self-deletion

`nix-builder-reaper.timer` on aule runs every minute. The decision is a
pure script, `modules/nix-builder/reap-decide.sh`, tested by
`nix build path:.#checks.x86_64-linux.nix-builder-reaper`:

1. Older than 6 h since creation: delete, **even during a build**. Logged
   at priority err.
2. Busy now: keep.
3. Busy within the last 10 min: keep.
4. Less than 50 min into the current billed hour: keep. The started hour
   is paid anyway; a build may still come.
5. Otherwise delete.

**Busy** means any of: a client connected to nix-daemon (each connection
is a child process of the main daemon; builds, copies and substitutions
run under one), a process of `nix-ssh` (gondor's ssh-ng session), or a
logind session (someone logged in, `clan machines update`). It is read
from live processes every minute rather than from a marker that builds
touch: a marker goes stale when a build crashes or a client hangs. The
last busy time lives in `/run`, so every boot starts with 10 minutes of
grace. Before deleting for idleness the reaper checks busy once more.

Creation time and server id come from the Hetzner API and the metadata
service (`169.254.169.254/hetzner/v1/metadata/instance-id`). The server
deletes itself with `DELETE /v1/servers/<id>`.

```sh
ssh root@aule journalctl -u nix-builder-reaper -n 20
```

## Daily use

```sh
just builder-up       # create, wait for ssh, print type and price
nix build ...         # builds go to aule
just builder-status   # server, age, snapshots, recorded address
just builder-down     # delete now (else it deletes itself)
```

After changing aule's config (or nixpkgs, to keep its closure warm):

```sh
just builder-snapshot   # up, clan machines update aule, snapshot, prune, down
```

`nix-builder snapshot` shuts the server down, snapshots it, deletes older
`machine=aule` snapshots and the server. If `clan machines update aule`
fails, the recipe stops and the server keeps running: fix and rerun, or
`just builder-down`.

## Bootstrap (one time)

1. **Hetzner Console**: in the project for aule, *Security → API tokens →
   Generate API token*, permission **Read & Write**. Under *Security → SSH
   keys* add your key (`~/.ssh/id_ed25519.pub`) so the bootstrap server
   accepts nixos-anywhere.
2. **Vars** (type the token when prompted), then commit `vars/`:

   ```sh
   clan vars generate gondor -g hcloud-token
   clan vars generate gondor -g nix-builder-ssh
   clan vars generate aule      # host key, state version, tor; joins shared vars
   clan vars check aule
   ```

3. **Deploy gondor**, so it has the `nix-builder` CLI, the ssh alias, the
   pinned host key and the builder key.
4. **Bootstrap server.** Use a small disk: a snapshot can only be restored
   onto a disk at least as large, and CCX33 has 240 GB. growpart enlarges
   the partition on the first boot of a bigger server. If CX23 is "not
   available", take the smallest x86 type that is (e.g. CPX22).

   ```sh
   export HCLOUD_TOKEN=$(cat /run/secrets/vars/hcloud-token/token)
   nix run nixpkgs#hcloud -- server create --name aule --type cx23 \
     --location fsn1 --image ubuntu-24.04 --ssh-key <your key name> \
     --label machine=aule
   nix run nixpkgs#hcloud -- server ip aule
   clan machines install aule --target-host root@<ip>
   ```

   Use the IP, not `aule`: Ubuntu's host key is not the pinned one. No
   `--update-hardware-config`: aule uses the generic qemu-guest profile so
   one image boots on CX and CCX hosts.
5. **Check and snapshot**:

   ```sh
   nix-builder up          # adopts the running server, writes the address
   ssh root@aule systemctl status nix-builder-reaper.timer
   sudo nix store info --store 'ssh-ng://nix-ssh@aule?ssh-key=/run/secrets/vars/nix-builder-ssh/id_ed25519'
   nix-builder snapshot    # shutdown, snapshot, delete
   ```

   The reaper is already active on the bootstrap server; it deletes it if
   you leave it idle near the end of an hour.
6. **First real run**: `just builder-up`, then build something and look
   for `on 'ssh-ng://nix-ssh@aule'` in the log. `just builder-status`.

## Failure modes

| symptom | cause | what happens / what to do |
| ------- | ----- | ------------------------- |
| `builder-up` creates a CCX33 | CX53 sold out in fsn1 and nbg1 | works, at ~4.7x the price; `builder-down` if not worth it |
| `no server type ... was available` | both types sold out in both locations | builds stay local; add a type or location in `modules/nix-builder/nix-builder.sh` |
| `no snapshot labelled machine=aule` | never bootstrapped, or snapshots deleted | bootstrap |
| builds wait ~5 s, then build locally | aule deleted itself less than a minute ago | `nix-builder-sync` removes the address within a minute |
| `Host key verification failed` | aule's `openssh` var was regenerated, the snapshot has the old key | `nix-builder up`, `clan machines update aule --target-host root@<ip>` (accept the old key once), `nix-builder snapshot` |
| a remote build fails mid-way | 6 h cap hit, or a build started in the second the reaper deleted | rerun; keepalives notice a vanished server within ~1 min |
| aule never deletes itself | token revoked or API down: the reaper unit fails every minute | `just builder-status`, `just builder-down`; check the token var |
| `nix-builder: cannot read the Hetzner token` | `hcloud-token` not generated or gondor not deployed | step 2 and 3 of the bootstrap |
| aule's disk fills | big build | nix collects garbage below 10 GiB free (`min-free`) |
