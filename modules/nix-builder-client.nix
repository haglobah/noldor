# gondor's side of the on-demand build machine aule (./nix-builder.nix):
# nix-daemon sends builds to it while it exists and builds locally while it
# does not. The `nix-builder` CLI and the `builder-*` recipes in the
# Justfile create and delete it. See docs/nix-builder.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  stateDir = "/var/lib/nix-builder";
  sshConfig = "${stateDir}/ssh_config";

  # aule's host key is a clan var, so it is the same on every server made
  # from the snapshot. Read from the repo: gondor's config cannot see
  # aule's vars otherwise.
  hostKeyFile = ../vars/per-machine/aule/openssh/ssh.id_ed25519.pub/value;
  hostKeyReady = builtins.pathExists hostKeyFile;

  nix-builder = pkgs.writeShellApplication {
    name = "nix-builder";
    runtimeInputs = [
      pkgs.hcloud
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      token_file=${generators.hcloud-token.files.token.path}
      ssh_config=${sshConfig}
    ''
    + builtins.readFile ./nix-builder/nix-builder.sh;
  };
in
{
  imports = [ ./nix-builder-vars.nix ];

  clan.core.vars.generators = {
    nix-builder-ssh.files.id_ed25519.deploy = true;
    # The CLI runs as beat.
    hcloud-token.files.token.owner = "beat";
  };

  environment.systemPackages = [ nix-builder ];

  warnings = lib.optional (!hostKeyReady) ''
    nix-builder: aule's host key is not generated yet, so gondor cannot
    verify it. Run `clan vars generate aule` (docs/nix-builder.md).
  '';

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "aule";
      sshUser = "nix-ssh";
      sshKey = generators.nix-builder-ssh.files.id_ed25519.path;
      protocol = "ssh-ng";
      system = "x86_64-linux";
      maxJobs = 4;
      # Only ranks remote builders against each other. Nix tries a free
      # remote slot before building locally anyway, and builds locally when
      # the connection fails.
      speedFactor = 2;
      supportedFeatures = [
        "big-parallel"
        "benchmark"
      ];
    }
  ];
  # aule fetches build inputs from cache.nixos.org and R2 itself instead of
  # receiving them over gondor's uplink.
  nix.settings.builders-use-substitutes = true;

  # `nix-builder up` writes `Host aule / HostName <ip>` to ${sshConfig}; ssh
  # takes the first value it sees, so the include wins over the fallback
  # below. Without the file, aule.invalid fails to resolve at once (RFC
  # 6761) and Nix builds locally without waiting. HostKeyAlias makes ssh
  # check the pinned key under `aule` instead of the changing IP.
  # Keepalives notice a server that deleted itself mid-build in ~1 min.
  programs.ssh.extraConfig = ''
    Match all
    Include ${sshConfig}
    Host aule
      HostName aule.invalid
      HostKeyAlias aule
      ConnectTimeout 5
      ServerAliveInterval 15
      ServerAliveCountMax 4
  '';
  programs.ssh.knownHosts.aule = lib.mkIf hostKeyReady {
    publicKey = lib.fileContents hostKeyFile;
  };

  systemd.tmpfiles.rules = [ "d ${stateDir} 0755 beat users -" ];

  # aule deletes itself without telling gondor; this drops the stale
  # address within a minute. It only calls the API while an address is
  # recorded.
  systemd.services.nix-builder-sync = {
    description = "Forget aule's address once the server is gone";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
      ExecStart = "${lib.getExe nix-builder} sync";
    };
  };
  systemd.timers.nix-builder-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };
}
