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
# The garden: beathagenlocher.com is served by the version (hotlustre's
# server/garden), readable without sign-in (publicHosts); www redirects to
# it. Both need DNS-only A records to cirdan (Cloudflare, grey cloud).
# The preview: preview.beathagenlocher.com, another site than flow's, so the
# browser runs the preview pane's pages in a process of their own and no dev
# page can block the app's main thread (hotlustre's server/frame-host.ts);
# the core lets it through without sign-in (frameHosts), the version admits
# only frames that came with a ticket from the app. DNS-only A record too.
# The core runs from the checkout: a deploy fast-forwards it to the locked
# hotlustre revision (flow-update-hotlustre) and restarts the core on a new one.
# Claude runs on Beat's subscription (var flow-claude, from
# `claude setup-token`). beat's GitHub key (var flow-github) is a key of
# Beat's GitHub account: it can push to every repository.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  domain = "flow.humane.tools";
  garden = "beathagenlocher.com";
  preview = "preview.${garden}";
  # The hotlustre revision this deploy locks (flake.lock): the checkout's core goes there.
  coreRev = inputs.hotlustre.rev;
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
    # Antithesis' CLI, for the antithesis-* skills in the agent's claude config.
    snouty
  ];

  # The version graph and the project repository to GitHub, ref by ref,
  # never forced; diverged refs go to refs/backup/ (./flow-backup.nix).
  backup = pkgs.callPackage ./flow-backup.nix { };
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

  imports = [
    ./flow-notes-peer.nix
    ./snouty.nix
    # The second app on this core's checkout (hotlustre's ADR-003).
    ./review.nix
  ];

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
    publicHosts = [ garden ];
    frameHosts = [ preview ];
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
      allow = [ "hagenlob@posteo.de" ];
      # todo-home prod's cookiePrefix (./todo-home.nix)
      cookiePrefix = "humane-shared";
    };
    # Review (./review.nix) fetches the patches only Flow can resolve, with
    # a bearer token the version checks; no sign-in, no cookies there.
    bearerPaths = [ "/api/patches" ];
    # Above it the unit is throttled and its page cache reclaimed, so the
    # rest of the 16 GB (Review's 1G, pushout-notes-sync, nix builds in
    # nix-daemon's cgroup, the kernel) keeps room. On 2026-11-19 with seven
    # agents at work: 7.8G anon + 2.5G cache, 13.7G peak. No MemoryMax: the
    # agents' claude CLIs and browsers run in this cgroup; one comes after a
    # week of numbers (`systemctl show hotlustre -p MemoryPeak`).
    memoryHigh = "12G";
  };
  # The checkout has to exist before the core can run from it, and so does
  # the version store, copied from gondor once: on an empty data directory
  # the core would start over from the seed.
  systemd.services.hotlustre = {
    unitConfig.ConditionPathExists = [
      "${checkout}/bin/hotlustre"
      "${cfg.dataDir}/core/repo.git"
    ];
    after = [
      "flow-clone-hotlustre.service"
      "flow-update-hotlustre.service"
    ];
    wants = [ "flow-update-hotlustre.service" ];
    restartTriggers = [ coreRev ];
    # Agents' builds, claude CLIs and headless browsers all run in this
    # unit. With the default OOMPolicy=stop, the kernel OOM-killing any one
    # of them stopped the whole unit, core and every version with it
    # (2026-11-19, oom_kill 28 since boot). The core restarts what it needs.
    serviceConfig.OOMPolicy = "continue";
  };

  # A deploy moves the checkout to the locked revision when that is a fast
  # forward; otherwise (local commits, another branch) it stays as it is.
  systemd.services.flow-update-hotlustre = {
    description = "Fast-forward the hotlustre checkout to the deployed revision";
    wantedBy = [ "multi-user.target" ];
    after = [
      "flow-clone-hotlustre.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    restartTriggers = [ coreRev ];
    unitConfig.ConditionPathIsDirectory = "${checkout}/.git";
    path = [
      pkgs.git
      pkgs.openssh
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "beat";
      WorkingDirectory = checkout;
    };
    script = ''
      git cat-file -e ${coreRev}^{commit} 2>/dev/null || git fetch --quiet origin
      if git merge-base --is-ancestor HEAD ${coreRev}; then
        git merge --ff-only --quiet ${coreRev}
      else
        echo "the checkout is not behind ${coreRev}: left as it is"
      fi
    '';
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
      ExecStart = lib.escapeShellArgs [
        (lib.getExe backup)
        checkout
        "refs/heads"
        "--"
        "${cfg.dataDir}/core/repo.git"
        "refs/heads"
        "refs/versions"
      ];
      # The set of diverged refs, to post only when it changes.
      StateDirectory = "flow-backup";
      # NTFY_TOPIC (./updater-alerts.nix); read by systemd as root.
      EnvironmentFile = vars.updater-alerts.files.env_file.path;
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
    virtualHosts.${garden}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
    virtualHosts."www.${garden}".extraConfig = ''
      redir https://${garden}{uri} permanent
    '';
    virtualHosts.${preview}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
  };
}
