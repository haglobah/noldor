# Notable's builds for the tablet: cirdan builds haglobah/notable's `main`
# whenever it moves and publishes the APK at
# https://flow.humane.tools/notable/ (notable-<code>.apk and latest.json),
# where Notable's updater finds it (notable: docs/plans/self-update.md,
# scripts/publish-apk.sh, which owns the build and the format).
#
# Every 10 minutes the timer fetches `main` into the unit's own clone (not
# ~/projects/notable, where agents work) and runs the clone's
# scripts/publish-apk.sh; a commit that is published already costs a fetch.
# A build now: `notable-release` (as beat, polkit lets it start the unit);
# the log: `journalctl -u notable-apk`.
#
# The signing key is gondor's debug keystore, which signed the app on the
# tablet (an update with another key would not install). It is not in vars:
# it sits at beat's ~/.config/notable-signing/notable.keystore, mode 600;
# its passwords are Android's debug defaults. publish-apk.sh refuses an APK
# signed with another certificate.
#
# The build gets 6 GB: on 2026-11-09 cirdan ran out of memory.
# The APKs need no sign-in (the tablet's updater has no session), so Caddy
# serves the directory itself, before the reverse proxy to Flow.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "flow.humane.tools";
  state = "/var/lib/notable-apk";
  clone = "${state}/notable";
  www = "${state}/www";
  home = "/home/beat";

  build = pkgs.writeShellApplication {
    name = "notable-apk-build";
    runtimeInputs = with pkgs; [
      git
      openssh
      nix
      jq
      coreutils
      gnused
      util-linux
    ];
    text = ''
      exec 9>${state}/lock
      flock -n 9 || { echo "a build is running already"; exit 0; }
      if [[ ! -d ${clone}/.git ]]; then
        git clone --quiet --branch main git@github.com:haglobah/notable.git ${clone}
      fi
      git -C ${clone} fetch --quiet origin main
      git -C ${clone} checkout --quiet --force -B main origin/main
      exec ${clone}/scripts/publish-apk.sh ${www}
    '';
  };

  release = pkgs.writeShellApplication {
    name = "notable-release";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      echo "building notable's main (journalctl -fu notable-apk follows it)"
      systemctl start notable-apk.service
      cat ${www}/latest.json
    '';
  };
in
{
  environment.systemPackages = [ release ];

  systemd.services.notable-apk = {
    description = "Build Notable's main and publish its APK for the tablet";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      HOME = home;
      GRADLE_USER_HOME = "${state}/gradle";
      STORE_FILE = "${home}/.config/notable-signing/notable.keystore";
      STORE_PASSWORD = "android";
      KEY_ALIAS = "androiddebugkey";
      KEY_PASSWORD = "android";
      EXPECTED_CERT_SHA256 = "61:20:5F:6C:CE:D0:A1:A4:77:8E:1A:80:52:74:93:D5:83:C4:6D:22:5D:7E:74:D5:01:2F:C5:84:B6:BC:65:BE";
      KEEP = "3";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "beat";
      ExecStart = lib.getExe build;
      # /var/lib/notable-apk, beat's; readable by Caddy.
      StateDirectory = "notable-apk";
      StateDirectoryMode = "0755";
      UMask = "0022";
      MemoryMax = "6G";
      MemorySwapMax = "1G";
      CPUQuota = "400%";
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "1h";
    };
  };
  systemd.timers.notable-apk = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitInactiveSec = "10min";
      RandomizedDelaySec = "1min";
    };
  };

  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "notable-apk.service" &&
          action.lookup("verb") == "start" &&
          subject.user == "beat") {
        return polkit.Result.YES;
      }
    });
  '';

  # Ahead of Flow's reverse proxy (./flow.nix): handle_path sorts first and
  # file_server answers, so /notable/ never reaches Flow's sign-in.
  services.caddy.virtualHosts.${domain}.extraConfig = lib.mkBefore ''
    handle_path /notable/* {
      root * ${www}
      @latest path /latest.json
      header @latest Cache-Control "no-cache"
      @apk path *.apk
      header @apk Cache-Control "public, max-age=31536000, immutable"
      file_server
    }
  '';
}
