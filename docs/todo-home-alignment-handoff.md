# Todo / HT alignment handoff

Objective: align Noldor's Todo deployment and backup integration with
`~/projects/ht`, including frontend billing configuration.

## Changes

- `flake.nix` / `flake.lock`: HT uses published tag `v0.5.0`, commit
  `159db06c1b7d966d539dc2fc24d55256cdd6f9fe`. Remote main and this tag matched
  when checked. Other working-tree lock changes were preserved.
- `clan.nix`: one `todoHomeBackupEnabled = false` flag gates the source,
  runner and watchdog imports together. No keys generated or hosts deployed.
- `modules/todo-home.nix`: use `frontend-deploy-dev`; explicitly retain billing
  test mode for both instances; remove the unused product-ID generator definition.
  Its existing stored secret was not read or deleted.
- `scripts/test-backup-restore.sh`: invoke the configured local oneshot service
  on Gondor; propagate errors; reject arguments. No direct backup mounting,
  credential retrieval or customer-data derivation inputs.
- Backup runbook and monitoring references updated for HT and the activation gate.
- HT: checkout reads `VITE_CREEM_PRODUCT_ID_SYNC_MONTHLY` through `src/billing.ts`;
  frontend derivation exposes `creemProductIdSyncMonthly`; both root and standalone
  deployment flakes read public IDs from `apps/todos/nix/billing-products.nix`.
  README/AGENTS environment documentation corrected. IDs are currently empty.

## Validation

- Restore wrapper: three Python unittest cases pass (success, service failure,
  rejected arguments). Tests stub direct credential/backup tools.
- HT billing: red/green test builds the browser configuration with Vite and checks
  that the public ID arrives and a synthetic backend secret does not.
- HT TypeScript check passes.
- Nix frontend argument evaluation returns the supplied synthetic product ID.
- Full Orthanc and Formenos system derivation evaluations pass.
- Full Gondor evaluation is blocked by existing `home/modules/emacs.nix` use of
  the removed nixpkgs `emacs30` alias. Record for a separate compatibility fix;
  no unrelated Emacs changes made.
- Shell syntax, changed Noldor Nix formatting and both repositories' diff whitespace
  checks pass. No full deployment-package builds or real restore tests performed.

## Remaining input / rollout

- Supply production and development public monthly Creem product IDs, or authorize
  reading the existing generated product-ID value. Confirm the intended billing
  mode; test mode is preserved until then. Populate HT's billing-products.nix with
  IDs matching each instance's credentials and mode.
- HT billing wiring is committed as `10726df`; populate the public IDs and
  publish a new validated
  release before repinning Noldor. The current remote v0.5.0 pin cannot include
  unpublished local changes; do not move the existing release tag.
- Before deployment, run HT's deployment preflight, take a consistent production
  backup, and follow its monorepo/topology runbooks.
- Activate backup rehearsals only through the documented coordinated rollout.
  No live production status, notifications, credentials or data were inspected.
