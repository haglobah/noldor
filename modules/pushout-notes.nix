# Notes on pushout at notes.humane.tools: its own humane tools app, with its
# own Automerge sync server, signed in with the humane tools account (Todos'
# auth server, ./todo-home.nix, which lists this origin in trustedOrigins).
# Module and docs: the pushout repo (notes/nix/module.nix, docs/plan-notes.md
# "A separate humane tools app").
# DNS: notes.humane.tools has an A record to orthanc.
# Admin: `pushout-notes-admin token EMAIL` mints a CLI token for author.ts
# once that account has signed in.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "notes.humane.tools";
  cfg = config.services.pushout-notes;
  # DynamicUser keeps the state under /var/lib/private.
  state = "/var/lib/private/pushout-notes";
  # borg copies files while the server runs; a live WAL-mode SQLite file can
  # be inconsistent, so back up an online snapshot of accounts.db as well
  # (docs/ is automerge-repo's files, written whole).
  snapshot = pkgs.writeShellScript "pushout-notes-db-snapshot" ''
    set -eu
    [ -e ${state}/accounts.db ] || exit 0
    mkdir -p ${state}/backup
    ${lib.getExe pkgs.sqlite} ${state}/accounts.db ".backup '${state}/backup/accounts.db'"
  '';
in
{
  services.pushout-notes = {
    enable = true;
    origin = "https://${domain}";
    htAuthUrl = "http://127.0.0.1:${toString config.services.todo-home.prod.authPort}";
    htAccountUrl = "https://todos.humane.tools";
    # Beat's release key (~/.local/share/pushout/keys/beat.json on his laptop).
    trustedKeys."eb28c90d5d264a5985cef88a4584f3f7863c83fdd863b50adf3d3f4cddcfefba" = "beat";
    # Beat's app doc, which author.ts publishes into; every other account
    # gets a clone that follows it.
    canonicalApp = "automerge:2TzrjzR6xQ9uYkoSxmv8UHPqgNQw";
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:${toString cfg.port}
  '';

  clan.core.state.pushout-notes = {
    folders = [ state ];
    preBackupScript = "${snapshot}";
  };
}
