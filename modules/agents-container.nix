# The agents' container on orthanc: notes' Claude worker (inputs.notes,
# nix/agent-module.nix) for notes.humane.tools, whose agents run shell
# commands without asking. It runs in a NixOS container (systemd-nspawn)
# with a network of its own, NATed out through orthanc, and reaches the app
# through its public origin like any client. Of orthanc's secrets it sees
# only the two it needs, bind-mounted read-only: the CLI token of Beat's
# account (shared with the code agent, pushout-notes.nix) and Beat's Claude
# subscription token.
#
#   nixos-container root-login agents        a shell inside
#   journalctl -M agents -u notes-agent      the worker's log
{
  config,
  lib,
  inputs,
  ...
}:
let
  vars = config.clan.core.vars.generators;
  secrets = "/run/agent-secrets";
in
{
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-agents" ];
    externalInterface = "enp1s0";
  };

  containers.agents = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.233.1.1";
    localAddress = "10.233.1.2";
    bindMounts = {
      "${secrets}/notes-token" = {
        hostPath = vars.pushout-notes-agent.files.notes-token.path;
        isReadOnly = true;
      };
      "${secrets}/claude-token" = {
        hostPath = vars.pushout-notes-agent-claude.files.claude-token.path;
        isReadOnly = true;
      };
    };
    config = {
      imports = [ inputs.notes.nixosModules.agent ];
      system.stateVersion = "26.05";
      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = [
        "1.1.1.1"
        "9.9.9.9"
      ];
      services.notes-agent = {
        enable = true;
        server = "https://notes.humane.tools";
        tokenFile = "${secrets}/notes-token";
        claudeTokenFile = "${secrets}/claude-token";
        workerId = "orthanc-agents";
        # orthanc has 2 cores and 3 GB.
        concurrency = 1;
      };
    };
  };

  # The worker's docs, the jobs' workspaces and Claude Code's sessions.
  clan.core.state.agents-container.folders = [ "/var/lib/nixos-containers/agents/var/lib/notes-agent" ];
}
