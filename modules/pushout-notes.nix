# Notes on pushout at notes.humane.tools, on cirdan: its own humane tools
# app, with its own Automerge sync server, signed in with the humane tools
# account (Todos' auth server on orthanc, ./todo-home.nix, which lists this
# origin in trustedOrigins).
# Module and docs: the pushout repo (notes/nix/module.nix, docs/plan-notes.md
# "A separate humane tools app").
# What it is for now: the hub hotlustre's notes relay through. cirdan's and
# gondor's hotlustre each keep a full copy of the notes and sync it with this
# server (hotlustre's server/plugins/notes.ts), which is the only link
# between the two. It moved here from orthanc on 2026-11-10: grown past 2 GB,
# it was OOM-killed every few minutes there and starved Todos prod with it.
# Until hotlustre's instances sync their notes with each other directly, it
# stays; then it goes.
# DNS: notes.humane.tools needs a DNS-only A record to cirdan.
# Admin: `pushout-notes-admin token EMAIL` mints a CLI token for author.ts
# once that account has signed in.
# The code agent (agent.enable) stays off here; its vars stay with orthanc's
# agents container (./agents-container.nix).
# Deploys: pushout's pull updater (pushout-notes-updater, every minute)
# deploys each push to pushout's main once nix-builds has built it on aule;
# a noldor deploy only changes the module and the seed release.
{
  config,
  inputs,
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
    # Todos prod's auth server is on orthanc; its public origin routes
    # /api/auth to it.
    htAuthUrl = "https://todos.humane.tools";
    htAccountUrl = "https://todos.humane.tools";
    # Beat's release key (~/.local/share/pushout/keys/beat.json on his
    # laptop), from pushout's flake, as the updater's releases carry it.
    trustedKeys = inputs.pushout.lib.notesDeployKeys;
    # Beat's app doc, which author.ts publishes into; every other account
    # gets a clone that follows it.
    canonicalApp = "automerge:2TzrjzR6xQ9uYkoSxmv8UHPqgNQw";
    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/pushout.git";
      branch = "main";
      interval = "*:0/1";
      # beat's GitHub key on cirdan (./flow.nix), a key of Beat's GitHub
      # account; pushout is private.
      sshKeyFile = config.clan.core.vars.generators.flow-github.files.key.path;
      # nix-builds (clanServices/nix-builds) builds pushout's buildJobs into
      # R2; this host only downloads. 60 ticks of a minute give a build an
      # hour before a commit counts as bad.
      substituteOnly = true;
      buildAttempts = 60;
      # Beat's own notes app: a plain warning, below prod's page
      # (./updater-alerts.nix).
      notify = {
        enable = true;
        environmentFile = config.clan.core.vars.generators.updater-alerts.files.env_file.path;
        priority = 4;
      };
    };
  };

  # The sync server loads docs into memory far beyond their size on disk; it
  # took 2 GB and more on orthanc. Capped, a runaway kills only itself, not
  # hotlustre next to it.
  systemd.services.pushout-notes-sync.serviceConfig.MemoryMax = "4G";

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:${toString cfg.port}
  '';

  clan.core.state.pushout-notes = {
    folders = [ state ];
    preBackupScript = "${snapshot}";
  };
}
