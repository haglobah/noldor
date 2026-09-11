# Daily todo-home recovery rehearsal

Configuration is prepared in `modules/todo-home-backup-{source,runner,watchdog,key}.nix`.
All three host imports are gated by `todoHomeBackupEnabled = false` in `clan.nix`.
It has **not been deployed**. No real backup was retrieved
for validation. Production-data retrieval/activation requires explicit approval:
a previous automatic approval review rejected restoring customer backups into a
local temporary directory. Source preparation and synthetic VM testing do not
lift that restriction.

## What runs

- Orthanc's existing daily 01:00 UTC Borg job runs a new pre-backup hook. The hook
  takes `/run/lock/todo-home-prod.lock`, gracefully stops `todo-home-prod`, snapshots
  SQLite through its backup API and copies legacy Yjs files, then restarts production.
  The application flushes buffered Yjs writes during graceful shutdown. A shell
  trap retries the restart on errors. This entails brief daily production downtime.
  Both application autoupdater paths use the same lock; deploy HT’s
  lock-aware updater before enabling the hook. Existing raw prod/dev Borg backups remain.
- The hook writes a private `backup.tar` and checksum/source-time metadata in
  `/var/lib/todo-home-restore-source`; Borg uploads them along with its other state.
  Snapshot failure fails the Borg prehook. A stale previous snapshot never becomes
  fresh just because Borg uploaded it again.
- Gondor runs `todo-home-backup-test` daily at 04:00 UTC plus up to five minutes of
  jitter. Persistent timers catch up after suspend. A restricted SSH command on
  Orthanc downloads only that snapshot from the newest **complete** Orthanc
  StorageBox archive. It does not fall back to an older successful archive if the
  newest one is broken. Source snapshots older than 26 hours fail validation.
- Gondor executes a newly booted isolated NixOS restore VM every run, checks data,
  authentication, v2 sync, persistence after restart, and access control. Production
  contents stay in runtime private state, never Nix derivations or shared caches.
  The matching pinned `ht` input supplies the prebuilt driver. Its app version
  must track the production release; Orthanc's independent tag autoupdater does not
  automatically advance this input. A passing rehearsal does not itself prove the revisions match; record and align
  the deployed release and driver revision when deploying this configuration.
- Gondor reports success or failure to a restricted SSH command on Formenos.
  Formenos checks every five minutes, alerts immediately after a failure signal
  or after 28 hours without success, repeats unresolved alerts every six hours,
  and sends recovery notification. It uses the **existing Gatus ntfy topic** and
  runtime secret. A dead/sleeping Gondor therefore cannot silence the alarm.

The dedicated shared Clan transport key is deployed privately only to Gondor.
Orthanc/Formenos authorize only their fixed commands (`restrict`, no shell,
forwarding, PTY, or arbitrary arguments). Gondor pins their existing public host
keys from Clan vars. No new external account, topic, or Borg secret copy is needed.

## Remaining activation steps, after approval

1. Publish and validate the intended HT release, then pin Noldor's `ht` input
   to that revision, aligning the VM backend with the deployed production release.
   Follow `~/projects/ht/apps/todos/docs/design/monorepo-deploy.md` and
   `~/projects/ht/apps/todos/docs/design/topology-deploy.md`. Keep unrelated Gondor/home edits out of
   the deployment unless independently intended.
2. Set `todoHomeBackupEnabled = true` locally to include all three modules and
   their generators. Before evaluating/building the receiver systems, run
   `clan vars generate gondor --generator todo-home-backup-transport` to generate
   the shared transport identity, then generate/deploy vars for Orthanc/Formenos
   using the normal Clan workflow. Do not deploy a partially enabled setup.
   No existing ntfy topic change is necessary. The public `key.pub` value must exist
   before normal receiver configuration evaluation. Never use the evaluation-only
   public key from `/tmp/todo-backup-host-eval` for deployment.
3. Deploy the reviewed configurations to Orthanc, Formenos and Gondor, building on
   Gondor. Ensure Orthanc has the updated lock-aware updater before the new snapshot
   hook runs. Formenos intentionally alarms until it receives the first success.
4. Run `systemctl start borgbackup-job-storagebox.service` on Orthanc and wait for
   successful completion, then `systemctl start todo-home-backup-test.service` on
   Gondor. These steps read and restore real production data and are gated on the
   explicit approval above. Inspect only sanitized service outcome and
   `/var/lib/todo-home-backup-test/last-success.json`; don't post customer data/logs.
5. Verify the actual ntfy notification route with a labelled test failure
   signal, then rerun a successful rehearsal to prove recovery reporting. This
   sends a real notification and has not been done during source preparation.

For a manual run on Gondor as root, `scripts/test-backup-restore.sh` starts the
same configured service and waits for its result. It uses the service's pinned
driver and private runtime archive; it does not mount backups or build customer
data into a derivation. A missing service or failed rehearsal returns nonzero.
The same production-data activation restriction applies to this manual command.

Useful status commands:

```sh
# Gondor
systemctl status todo-home-backup-test.service todo-home-backup-test.timer
journalctl -u todo-home-backup-test.service
# Orthanc
systemctl status borgbackup-job-storagebox.service
# Formenos
systemctl status todo-home-backup-watchdog.service todo-home-backup-watchdog.timer
```

## Limits

Only **production** todo-home is restore-tested. Development data retains its
existing backup coverage. Fetching through Orthanc exercises StorageBox retrieval
with its actual existing credentials, but still requires Orthanc alive; this is
not a full rehearsal of recovering after Orthanc and its secrets are destroyed.
That outage causes a missed/failure alert. A separate offline credential recovery
procedure is still needed. The watchdog itself lives on Formenos and shares its
availability and ntfy delivery dependencies. It cannot alert while Formenos is
also down. The transport identity gives Gondor no arbitrary remote shell access.
The ntfy topic remains on Formenos.
