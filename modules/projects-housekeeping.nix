# Clears what Flow's agents leave behind on cirdan. Each task gets a git
# worktree in ~/projects (miri-media-campaign-typos, ForumMagnum-shorten …),
# each with its own node_modules, and scratch clones go to /tmp; nothing
# removed them. On 2026-11-19 ~70 miri worktrees (34 GB) and 17 GB in /tmp
# filled the disk, and hotlustre's version server died on ENOSPC mid-turn.
#
# The rule: a worktree is disposable once its work is on GitHub. Daily, a
# linked worktree of ~/projects (never a main clone) that no process runs
# in and that nobody touched for 3 days (no file outside node_modules, no
# commit or checkout) is
# - removed, with its entries in hotlustre's preview/servers.json, when it
#   is clean, every commit is on a remote, and each ignored file is either
#   regenerable (node_modules, dist, .astro …) or the main checkout's copy;
# - else kept, minus its regenerable outputs (`bun install` brings them back),
#   and listed with its reasons in the unit's log.
# Try it: `projects-housekeeping --dry-run`; the log:
# `journalctl -u projects-housekeeping`.
#
# /tmp keeps files 3 days instead of systemd's 10.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  housekeeping = pkgs.writeShellApplication {
    name = "projects-housekeeping";
    runtimeInputs = with pkgs; [
      git
      jq
      coreutils
      findutils
      diffutils
      gnugrep
    ];
    text = builtins.readFile ./projects-housekeeping.sh;
  };
in
{
  environment.systemPackages = [ housekeeping ];

  systemd.services.projects-housekeeping = {
    description = "Remove the worktrees in ~/projects whose work is on GitHub";
    environment = {
      HOME = "/home/beat";
      STALE_DAYS = "3";
      SERVERS_JSON = "${config.services.hotlustre.dataDir}/appdata/preview/servers.json";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
      ExecStart = lib.getExe housekeeping;
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.projects-housekeeping = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "04:30";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };

  # systemd's tmp.conf says `q /tmp 1777 root root 10d`; of two lines for
  # one path the file whose name sorts first wins.
  systemd.tmpfiles.settings."00-tmp-age"."/tmp".q = {
    mode = "1777";
    user = "root";
    group = "root";
    age = "3d";
  };
}
