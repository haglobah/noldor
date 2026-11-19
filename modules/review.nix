# Review on cirdan at review.humane.tools: hotlustre's second app
# (hotlustre's docs/adr/ADR-003-apps.md), a core of its own beside Flow's
# (./flow.nix), from the same checkout and as the same user: unit
# hotlustre-review.service, port 8050, data in ~/apps/review. It has its own
# version graph, state and claude login (~/apps/review/appdata/claude-config,
# made once with `claude auth login`), the same humane tools sign-in as Flow,
# and a memory limit of its own: it is killed alone, Flow is not.
# Imported by ./flow.nix.
#
# Objects cross by reference: Review asks Flow for patches at Flow's bearer
# door /api/patches (./flow.nix); others reach Review's share links (/s,
# /api/share) and its API (/api/review) with a bearer token, no sign-in.
#
# Made by hand once, before the first start (the unit waits for it):
# `hotlustre new ~/apps/review --seed ~/apps/review-seed`. Its version graph
# goes to GitHub (review-backup, once its repo.git has an origin) and to a
# mirror under /srv a guest's instance can read (review-mirror).
# DNS: review.humane.tools needs a DNS-only A record to cirdan;
# todo-home's trustedOrigins on orthanc lists the origin (./todo-home.nix).
#
# Guests (ADR-003 "Sharing Review with the friend", package G1): each one is
# an instance review-<name> as a system user of its own, data in
# /var/lib/hotlustre-review-<name>, following Review's versions from the
# mirror, at <name>.review.humane.tools. None yet: see `guests` below.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  domain = "review.humane.tools";
  home = "/home/beat";
  flow = config.services.hotlustre;
  cfg = config.services.hotlustre.instances.review;
  repo = "${cfg.dataDir}/core/repo.git";
  coreRev = inputs.hotlustre.rev;
  owner = "hagenlob@posteo.de";
  backup = pkgs.callPackage ./flow-backup.nix { };

  # Review's versions, readable by the guests' users (group review-mirror):
  # they cannot read beat's home and have no ssh key, so they follow this.
  mirror = "/srv/hotlustre/review.git";

  # A guest per entry: name (lower case, the host's first label) = { email;
  # port; }. Off until G1; e.g.
  #   guests.maria = { email = "maria@example.com"; port = 8051; };
  # gives the user hl-review-maria, hotlustre-review-maria.service on 8051
  # and maria.review.humane.tools (DNS: an A record, or *.review once), and
  # wants https://maria.review.humane.tools in todo-home's trustedOrigins and
  # a claude login in /var/lib/hotlustre-review-maria/appdata/claude-config.
  guests = { };
  guestUser = name: "hl-review-${name}";
in
{
  services.hotlustre.instances = {
    review = {
      port = 8050;
      user = "beat";
      inherit (flow) checkout extraPackages;
      dataDir = "${home}/apps/review";
      seed = "${home}/apps/review-seed";
      ht = {
        inherit (flow.ht) authUrl allow cookiePrefix;
        admin = [ owner ];
      };
      # The contract's doors, a link's page and its assets, Review's own API.
      bearerPaths = [
        "/api/share"
        "/s"
        "/api/review"
      ];
      memoryHigh = "768M";
      memoryMax = "1G";
    };
  }
  // lib.mapAttrs' (
    name: guest:
    lib.nameValuePair "review-${name}" {
      inherit (guest) port;
      user = guestUser name;
      # dataDir: the default /var/lib/hotlustre-review-<name> (0700, its
      # own). No checkout: the core runs from the store, which it can read.
      ht = {
        inherit (flow.ht) authUrl cookiePrefix;
        allow = [
          guest.email
          owner
        ];
        admin = [ owner ];
      };
      follow = {
        name = "review";
        url = mirror;
      };
      memoryMax = "1G";
    }
  ) guests;

  users.users = lib.mapAttrs' (
    name: _:
    lib.nameValuePair (guestUser name) {
      isSystemUser = true;
      group = guestUser name;
      extraGroups = [ "review-mirror" ];
      home = "/var/lib/hotlustre-review-${name}";
    }
  ) guests;
  users.groups = {
    review-mirror = { };
  }
  // lib.mapAttrs' (name: _: lib.nameValuePair (guestUser name) { }) guests;

  # As Flow's (./flow.nix): the checkout and the app must exist, a deploy
  # restarts the core on the new revision, and an OOM-killed agent process
  # leaves the core running.
  systemd.services.hotlustre-review = {
    unitConfig.ConditionPathExists = [
      "${cfg.checkout}/bin/hotlustre"
      repo
    ];
    after = [
      "flow-clone-hotlustre.service"
      "flow-update-hotlustre.service"
    ];
    wants = [ "flow-update-hotlustre.service" ];
    restartTriggers = [ coreRev ];
    serviceConfig.OOMPolicy = "continue";
  };

  # Review's version graph to GitHub, as flow-backup does Flow's, once the
  # repository has an origin (a private haglobah/review-versions).
  systemd.services.review-backup = {
    description = "Push Review's version graph to GitHub";
    unitConfig.ConditionPathIsDirectory = repo;
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
      # No origin yet: skipped, not failed.
      ExecCondition = lib.escapeShellArgs [
        (lib.getExe pkgs.git)
        "-C"
        repo
        "config"
        "remote.origin.url"
      ];
      ExecStart = lib.escapeShellArgs [
        (lib.getExe backup)
        repo
        "refs/heads"
        "refs/versions"
      ];
      StateDirectory = "review-backup";
      # NTFY_TOPIC (./updater-alerts.nix); read by systemd as root.
      EnvironmentFile = config.clan.core.vars.generators.updater-alerts.files.env_file.path;
    };
  };
  systemd.timers.review-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "9min";
      OnUnitActiveSec = "20min";
      RandomizedDelaySec = "2min";
    };
  };

  # The mirror: only refs/versions/* and refs/sync/* (what a follower
  # fetches; hotlustre's core/sync.ts), forced and pruned, so it holds
  # Review's graph and nothing else of beat's. Pushed whenever Review's core
  # moves refs/sync/current (each activation): a path unit, so a publish is
  # there at once and nothing runs while nothing changes; and once at boot,
  # for what changed while it was down. Harmless without guests: its group
  # has nobody in it yet.
  systemd.tmpfiles.settings.review-mirror = {
    "/srv/hotlustre".d = {
      mode = "0755";
      user = "root";
      group = "root";
    };
    # setgid: everything in it stays in the group.
    ${mirror}.d = {
      mode = "2750";
      user = "beat";
      group = "review-mirror";
    };
  };
  systemd.services.review-mirror = {
    description = "Mirror Review's versions to ${mirror} for the guests' instances";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    unitConfig.ConditionPathIsDirectory = repo;
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
    };
    script = ''
      # Files 0640, directories 0750: the group reads, nobody else.
      [ -f ${mirror}/HEAD ] || git init --quiet --bare --shared=0640 ${mirror}
      git -C ${repo} push --quiet --force --prune ${mirror} \
        '+refs/versions/*:refs/versions/*' '+refs/sync/*:refs/sync/*'
    '';
  };
  systemd.paths.review-mirror = {
    wantedBy = [ "paths.target" ];
    pathConfig.PathChanged = "${repo}/refs/sync/current";
  };
  # A guest's core fetches the mirror as its own user; git refuses a
  # repository someone else owns unless it is listed here.
  environment.etc.gitconfig.text = ''
    [safe]
      directory = ${mirror}
  '';

  services.caddy.virtualHosts = {
    # As flow.humane.tools: Caddy flushes event streams (text/event-stream)
    # by itself, so a plain reverse_proxy carries them.
    ${domain}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';
  }
  // lib.mapAttrs' (
    name: guest:
    lib.nameValuePair "${name}.${domain}" {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString guest.port}
      '';
    }
  ) guests;
}
