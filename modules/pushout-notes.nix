# Notes on pushout at notes.humane.tools: its own humane tools app, with its
# own Automerge sync server, signed in with the humane tools account (Todos'
# auth server, ./todo-home.nix, which lists this origin in trustedOrigins).
# Module and docs: the pushout repo (notes/nix/module.nix, docs/plan-notes.md
# "A separate humane tools app").
# DNS: notes.humane.tools has an A record to orthanc.
# Admin: `pushout-notes-admin token EMAIL` mints a CLI token for author.ts
# once that account has signed in.
# The code agent (pushout-notes-agent) works as Beat's account, the admin's,
# with a CLI token of it (var pushout-notes-agent/notes-token: mint it with
# `pushout-notes-admin token EMAIL agent` here). On first start it asks to be
# trusted: approve "code agent …" in the app's code pane. Claude runs on
# Beat's subscription (var pushout-notes-agent-claude/claude-token, from
# `claude setup-token`).
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
    htAuthUrl = "http://127.0.0.1:${toString config.services.todo-home.prod.authPort}";
    htAccountUrl = "https://todos.humane.tools";
    # Beat's release key (~/.local/share/pushout/keys/beat.json on his
    # laptop), from pushout's flake, as the updater's releases carry it.
    trustedKeys = inputs.pushout.lib.notesDeployKeys;
    # Beat's app doc, which author.ts publishes into; every other account
    # gets a clone that follows it.
    canonicalApp = "automerge:2TzrjzR6xQ9uYkoSxmv8UHPqgNQw";
    agent = {
      enable = true;
      tokenFile = config.clan.core.vars.generators.pushout-notes-agent.files.notes-token.path;
      claudeTokenFile =
        config.clan.core.vars.generators.pushout-notes-agent-claude.files.claude-token.path;
    };
    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/pushout.git";
      branch = "main";
      interval = "*:0/1";
      # orthanc's host key, a key of Beat's GitHub account.
      sshKeyFile = config.clan.core.vars.generators.openssh.files."ssh.id_ed25519".path;
      # nix-builds (clanServices/nix-builds) builds pushout's buildJobs into
      # R2; orthanc only downloads. 60 ticks of a minute give a build an
      # hour before a commit counts as bad.
      substituteOnly = true;
      buildAttempts = 60;
    };
  };

  clan.core.vars.generators.pushout-notes-agent = {
    files.notes-token = { };
    prompts.notes-token = {
      type = "hidden";
      description = "A CLI token of Beat's notes.humane.tools account: `pushout-notes-admin token EMAIL agent` on orthanc";
    };
    script = ''cp "$prompts/notes-token" "$out/notes-token"'';
  };
  # Beat's Claude subscription, which the agent's Claude Code runs on.
  clan.core.vars.generators.pushout-notes-agent-claude = {
    files.claude-token = { };
    prompts.claude-token = {
      type = "hidden";
      description = "Beat's Claude subscription token for the code agent: `claude setup-token`";
    };
    script = ''cp "$prompts/claude-token" "$out/claude-token"'';
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:${toString cfg.port}
  '';

  clan.core.state.pushout-notes = {
    folders = [ state ];
    preBackupScript = "${snapshot}";
  };
  # The agent's key, which the app doc trusts, and Claude Code's sessions.
  clan.core.state.pushout-notes-agent.folders = [ "/var/lib/private/pushout-notes-agent" ];
}
