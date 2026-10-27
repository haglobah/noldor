# hotlustre on cirdan at flow.humane.tools: the self-changing app, run as
# beat from a checkout of its repository, as on gondor. Its agent's shell
# sees /home/beat and Beat's repositories in ~/projects, cloned on first use
# with `repo NAME` (./repo-command.nix); only
# hotlustre's core and version store are read-only to it (bubblewrap).
# Module and docs: the hotlustre repo (nix/module.nix, docs/handoff.md).
# Needs inputs.hotlustre.nixosModules.default, imported in clan.nix.
#
# Sign-in: humane tools (Todos' Better Auth on orthanc), Beat's account
# only; the core checks it, so no version can drop it. todo-home's
# trustedOrigins on orthanc lists this origin (./todo-home.nix).
# DNS: flow.humane.tools needs a DNS-only A record to cirdan.
# Claude runs on Beat's subscription (var flow-claude, from
# `claude setup-token`). beat's GitHub key (var flow-github) is a key of
# Beat's GitHub account: it can push to every repository.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "flow.humane.tools";
  cfg = config.services.hotlustre;
  vars = config.clan.core.vars.generators;
  home = "/home/beat";
  checkout = "${home}/projects/hotlustre";
  tools = with pkgs; [
    git
    openssh
    gh
    jq
    nix
    gnumake
    gcc
    python3
    nodejs
  ];

  # The version graph and the project repository to GitHub; nothing forced,
  # a rejected push fails the unit visibly.
  backup = pkgs.writeShellApplication {
    name = "flow-backup";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      git -C ${checkout} push --quiet origin 'refs/heads/*:refs/heads/*'
      git -C ${cfg.dataDir}/core/repo.git push --quiet origin \
        'refs/heads/*:refs/heads/*' 'refs/versions/*:refs/versions/*'
    '';
  };
in
{
  users.users.beat = {
    isNormalUser = true;
    inherit home;
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILD4jhHznn3K7uZGhNTu3En3vDyiLmbColfok2Qm/MKS beat@gondor"
    ];
  };
  programs.fish.enable = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  environment.systemPackages = tools;

  programs.ssh.extraConfig = ''
    Host github.com
      IdentityFile ${vars.flow-github.files.key.path}
  '';
  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  environment.etc.gitconfig.text = ''
    [user]
      name = Beat Hagenlocher
      email = bah@posteo.de
    [init]
      defaultBranch = main
  '';

  clan.core.vars.generators.flow-github = {
    files.key.owner = "beat";
    files."key.pub".secret = false;
    runtimeInputs = [ pkgs.openssh ];
    script = ''ssh-keygen -q -t ed25519 -N "" -C "beat@cirdan" -f "$out/key"'';
  };
  clan.core.vars.generators.flow-claude = {
    files.env.owner = "beat";
    prompts.claude-token = {
      type = "hidden";
      description = "Beat's Claude subscription token for hotlustre's agent: `claude setup-token`";
    };
    script = ''echo "CLAUDE_CODE_OAUTH_TOKEN=$(cat "$prompts/claude-token")" > "$out/env"'';
  };

  services.hotlustre = {
    enable = true;
    user = "beat";
    inherit checkout;
    dataDir = "${checkout}/data";
    # Everything installed system-wide: the tools above and `repo`.
    extraPackages = [ config.system.path ];
    environmentFile = vars.flow-claude.files.env.path;
    # gondor fetches from and pushes to this instance (./flow-gondor.nix);
    # this one merges when the two diverged.
    sync = {
      instance = "cirdan";
      merges = true;
    };
    ht = {
      authUrl = "https://todos.humane.tools";
      allow = [ "bah@posteo.de" ];
      # todo-home prod's cookiePrefix (./todo-home.nix)
      cookiePrefix = "humane-shared";
    };
  };
  # The checkout has to exist before the core can run from it, and so does
  # the version store, copied from gondor once: on an empty data directory
  # the core would start over from the seed.
  systemd.services.hotlustre = {
    unitConfig.ConditionPathExists = [
      "${checkout}/bin/hotlustre"
      "${cfg.dataDir}/core/repo.git"
    ];
    after = [ "flow-clone-hotlustre.service" ];
  };

  systemd.services.flow-clone-hotlustre = {
    description = "Clone hotlustre, which the service runs from";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!${checkout}";
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
      ExecStart = "${lib.getExe config.programs.repo.package} hotlustre";
    };
  };

  systemd.services.flow-backup = {
    description = "Push hotlustre and its version graph to GitHub";
    unitConfig.ConditionPathIsDirectory = "${cfg.dataDir}/core/repo.git";
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
      ExecStart = lib.getExe backup;
    };
  };
  systemd.timers.flow-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "7min";
      OnUnitActiveSec = "20min";
      RandomizedDelaySec = "2min";
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
  };
}
