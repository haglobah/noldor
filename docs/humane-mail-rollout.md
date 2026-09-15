# Humane Mail rollout on orthanc

Objective: run Mail (`mail.humane.tools`, `dev.mail.humane.tools`) on orthanc
next to Todo, with the Todo bridge and shared sessions configured on both
sides. Source of truth for the module: `ht/apps/mail/docs/production.md`.

## What the commit does

- `modules/humane-mail.nix`: prod (port 3201, `v*` tags) and dev (port 3301,
  `main`) instances of `services.humane-mail`, each with its own clan vars
  generator that mints `CREDENTIALS_KEY`, `MAIL_BRIDGE_TOKEN` and a VAPID pair
  and prompts for the VAPID contact. The same run writes the Todo side's
  `MAIL_BRIDGE_TOKEN` + `MAIL_BRIDGE_ORIGIN`, so the token matches by
  construction. Data dirs join `clan.core.state`.
- `modules/todo-home.nix`: each Todo instance loads its Mail bridge env file,
  trusts its Mail origin, and prod turns on the shared cookie domain
  `humane.tools` with prefix `humane-shared`; dev gets prefix `humane-dev` and
  no parent domain.
- `clan.nix`: orthanc imports `inputs.ht.nixosModules.mail` and the module.

## Rollout

1. DNS: `mail.humane.tools` and `dev.mail.humane.tools` → orthanc. Caddy needs
   80/443 (already open) to obtain certificates.
2. `clan vars generate orthanc` — answer the two VAPID contact prompts with a
   `mailto:` address. Do not regenerate later: a new `CREDENTIALS_KEY` orphans
   every stored mailbox.
3. `clan machines update orthanc`. Todo restarts with the new cookie prefix:
   every user signs in once more. Check `systemctl status humane-mail-prod
   humane-mail-dev` and `curl --fail https://mail.humane.tools/api/health`.
4. In Mail, sign in with a Todo account, add a mailbox, and walk the checks
   from production.md: two-user isolation, a todo completion/reopen round
   trip, sign-out from Mail, notifications while Mail is closed.
5. Tag ht (`v*`) once dev looks right; the prod updater picks the highest tag.

## Not in this commit

- Gatus probes for the Mail hosts in `modules/monitoring.nix` (formenos).
  Adding them before orthanc serves Mail would page immediately; add them
  right after step 3 with `/` and `/api/health`.
- The `flake.lock` pin of ht stays at 90275d2: the Mail module and packages
  are unchanged since, and the updaters build from git on their own.
- `AUTH_OWNER_USER_ID`: only for migrating a pre-existing single-owner Mail
  database. There is none on orthanc.
