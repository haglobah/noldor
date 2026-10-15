# Notes sync server: Automerge sync and accounts for the Notes PWA and
# desktop app. Module and docs live in the notes repo (nix/module.nix,
# server/README.md, docs/HANDOFF.md).
# Accounts: `notes-admin user add <name>` on formenos.
# Needs inputs.notes.nixosModules.default, imported in clan.nix: `inputs`
# arrives via _module.args and can't be used in this module's imports.
# DNS: notes.hagenlocher.me needs a DNS-only (not proxied) A record to
# formenos at Cloudflare, like notable.hagenlocher.me, so Caddy can get its
# certificate and WebSockets reach the server directly.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "notes.hagenlocher.me";
  cfg = config.services.notes-server;
  # borg copies files while the server runs; a live WAL-mode SQLite file can
  # be inconsistent, so back up an online snapshot instead.
  snapshot = pkgs.writeShellScript "notes-db-snapshot" ''
    set -eu
    # sqlite3 would create a missing database as root, locking the service out.
    [ -e ${cfg.stateDir}/notes.db ] || exit 0
    mkdir -p ${cfg.stateDir}/backup
    ${lib.getExe pkgs.sqlite} ${cfg.stateDir}/notes.db ".backup '${cfg.stateDir}/backup/notes.db'"
  '';
in
{
  services.notes-server = {
    enable = true;
    # 3030 is todo-home's sync port elsewhere in the clan, 3040 is notable.
    port = 3050;
    publicOrigin = "https://${domain}";
    # Behind Caddy every request comes from 127.0.0.1; the login rate limit
    # needs the client address from X-Forwarded-For.
    trustProxy = true;
    # extraOrigins keeps the module default: the Tauri desktop app's origins.
  };

  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
  };

  clan.core.state.notes = {
    folders = [ cfg.stateDir ];
    preBackupScript = "${snapshot}";
  };
}
