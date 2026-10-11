# Notable sync server: Automerge sync, blob store and accounts for the
# Notable e-ink app and its PWA. Module and docs live in the notable repo
# (web/nix/module.nix, web/server/README.md).
# Accounts: `notable-admin user add <name>` on formenos.
# Needs inputs.notable.nixosModules.default, imported in clan.nix: `inputs`
# arrives via _module.args and can't be used in this module's imports.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "notable.hagenlocher.me";
  cfg = config.services.notable-server;
  # borg copies files while the server runs; a live WAL-mode SQLite file can
  # be inconsistent, so back up an online snapshot instead.
  snapshot = pkgs.writeShellScript "notable-db-snapshot" ''
    set -eu
    # sqlite3 would create a missing database as root, locking the service out.
    [ -e ${cfg.stateDir}/notable.db ] || exit 0
    mkdir -p ${cfg.stateDir}/backup
    ${lib.getExe pkgs.sqlite} ${cfg.stateDir}/notable.db ".backup '${cfg.stateDir}/backup/notable.db'"
  '';
in
{
  services.notable-server = {
    enable = true;
    # 3030 is todo-home's sync port elsewhere in the clan; keep them apart.
    port = 3040;
    publicOrigin = "https://${domain}";
    # Behind Caddy every request comes from 127.0.0.1; the login rate limit
    # needs the client address from X-Forwarded-For.
    trustProxy = true;
  };

  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
  };

  clan.core.state.notable = {
    folders = [ cfg.stateDir ];
    preBackupScript = "${snapshot}";
  };
}
