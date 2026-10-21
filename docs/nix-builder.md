# On-demand build machine `aule`

## What it is

`aule` is a Hetzner Cloud server that exists only while there is something
to build. It is role `builder` of the nix-builds clan service
(`clanServices/nix-builds/README.md`):

- The **scheduler on orthanc** creates it from its newest snapshot when a
  registered repo's commit has outputs missing from R2, and sends the
  derivations over `ssh-ng` as the untrusted user `nix-ssh`.
- aule builds them, then **signs and pushes** the outputs to R2 with its own
  key (`nix-builds-builder-key`), from its post-build hook.
- It **deletes itself** when idle (below).

gondor does not build on aule. gondor only refreshes the snapshot and can
look at or delete the server.

| File                                        | What                                                   |
| ------------------------------------------- | ------------------------------------------------------ |
| `machines/aule/`                            | hardware: qemu-guest profile, disko, growpart          |
| `clanServices/nix-builds/builder.nix`       | `nix-ssh`, the reaper, push settings                   |
| `clanServices/nix-builds/reaper/`           | the pure self-deletion decision                        |
| `modules/nix-builder-operator.nix`          | gondor: `nix-builder` CLI and the ssh alias `aule`     |
| `modules/nix-builder/nix-builder.sh`        | the CLI behind the `builder-*` recipes                 |

## Costs

Hetzner bills every started hour while a server exists, even powered off.
Prices since 15 June 2026, Germany, without VAT:

- **CX53** (16 shared vCPU, 32 GB): about €0.047/h. Tried first; often
  sold out since September 2026.
- **CCX33** (8 dedicated vCPU, 32 GB): €0.2219/h. The fallback.
- **Snapshot**: billed per GB per month (unverified: about $0.014/GB).

## Self-deletion

`nix-builder-reaper.timer` on aule runs every minute. The decision is a
pure script, `clanServices/nix-builds/reaper/reap-decide.sh`, tested by
`checks.x86_64-linux.nix-builder-reaper`:

1. Older than 6 h since creation: delete, **even during a build**. Logged
   at priority err.
2. Busy now: keep.
3. Busy within the last 10 min: keep.
4. Less than 50 min into the current billed hour: keep. The started hour
   is paid anyway; another commit may still come.
5. Otherwise delete.

**Busy** means any of: a client connected to nix-daemon, a process of
`nix-ssh` (the scheduler's session), a running `nix-cache-push.service`
(an upload), or a logind session (someone logged in, `clan machines
update`). It is read from live processes every minute. The last busy time
lives in `/run`, so every boot starts with 10 minutes of grace. Before
deleting for idleness the reaper checks busy once more.

```sh
ssh root@aule journalctl -u nix-builder-reaper -n 20
```

## Operating it from gondor

```sh
just builder-status     # server, age, snapshots, recorded address
just builder-down       # delete now (else it deletes itself)
just builder-snapshot   # up, clan machines update aule, warm, snapshot, prune, down
```

Run `builder-snapshot` after changing aule's config, or after a nixpkgs
or dependency bump in a registered repo: a fresh aule only finds in its
store what the snapshot holds, and downloads the rest for every build. It
boots the old image, deploys the current config (built on aule itself),
realises the build inputs of the repos in the Justfile's `builder_warm`
(`nix-builder warm`), shuts it down, snapshots it, deletes older
`machine=aule` snapshots and the server.

`warm` evaluates on gondor and builds each job's `inputDerivation` on
aule, not the job itself. An output already in aule's store would never
run the post-build hook, so it would never reach R2 and the scheduler
would wait for it in vain. If `clan machines
update aule` fails, the recipe stops and the server keeps running: fix and
rerun, or `just builder-down`.

## Bootstrap (one time)

1. **Hetzner Console**: in the project for aule, *Security → API tokens →
   Generate API token*, permission **Read & Write**. Under *Security → SSH
   keys* add your key (`~/.ssh/id_ed25519.pub`) so the bootstrap server
   accepts nixos-anywhere.
2. **Vars**: the steps in `clanServices/nix-builds/README.md`, then commit
   `vars/`.
3. **Deploy gondor**, so it has the `nix-builder` CLI, the ssh alias and
   aule's pinned host key.
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
   nix-builder snapshot    # shutdown, snapshot, delete
   ```

6. **First real run**: deploy orthanc, push a commit to a registered repo,
   and follow `journalctl -u nix-builds -f` on orthanc.

## Failure modes

| symptom | cause | what happens / what to do |
| ------- | ----- | ------------------------- |
| the scheduler creates a CCX33 | CX53 sold out in fsn1 and nbg1 | works, at ~4.7x the price |
| `no server type available` | both types sold out in both locations | job result `error`; the next poll retries; add a type or location in the scheduler settings |
| `no snapshot labelled machine=aule` | never bootstrapped, or snapshots deleted | bootstrap |
| `Host key verification failed` | aule's `openssh` var was regenerated, the snapshot has the old key | `nix-builder up`, `clan machines update aule --target-host root@<ip>` (accept the old key once), `nix-builder snapshot` |
| a build fails mid-way | 6 h cap hit, or the reaper deleted aule in that second | the scheduler sees the server gone, records `error` and retries on the next poll |
| aule never deletes itself | token revoked or API down: the reaper unit fails every minute | `just builder-status`, `just builder-down`; check the token var |
| aule's disk fills | big build | nix collects garbage below 10 GiB free (`min-free`) |
