{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    clan.core.state.immich = {
      folders = [
        "/var/lib/immich"
      ];
    };
    services.caddy = {
      enable = true;
      virtualHosts."photos.hagenlocher.me" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString config.services.immich.port}
        '';
      };
    };
    services.immich = {
      enable = true;
      host = "0.0.0.0";
      machine-learning.enable = false;
      openFirewall = true;
    };

    systemd.services.immich-server.serviceConfig.Restart = lib.mkForce "always";

    # Periodically check if the CIFS mount is stale and remount it
    systemd.services.immich-mount-watchdog = {
      description = "Check and remount stale Immich CIFS mount";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "immich-mount-watchdog" ''
          if ${pkgs.util-linux}/bin/mountpoint -q /var/lib/immich; then
            # Force a real I/O operation — cached stat won't catch a dead connection
            if ! ${pkgs.coreutils}/bin/timeout 5 ${pkgs.coreutils}/bin/ls /var/lib/immich/upload/ >/dev/null 2>&1; then
              echo "Immich mount is stale, remounting..."
              ${pkgs.util-linux}/bin/umount -l /var/lib/immich || true
              # Trigger automount by accessing the path
              if ${pkgs.coreutils}/bin/timeout 10 ${pkgs.coreutils}/bin/ls /var/lib/immich/ >/dev/null 2>&1; then
                echo "Remount succeeded, restarting Immich..."
                /run/current-system/sw/bin/systemctl restart immich-server
              else
                echo "Remount failed — storage box still unreachable"
              fi
            fi
          fi
        '';
      };
    };
    systemd.timers.immich-mount-watchdog = {
      description = "Periodically check Immich CIFS mount health";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "2min";
        RandomizedDelaySec = "30s";
      };
    };

    environment.systemPackages = [ pkgs.cifs-utils ];
    fileSystems."/var/lib/immich" = {
      device = "//u366465-sub7.your-storagebox.de/u366465-sub7";
      fsType = "cifs";
      options = [
        "vers=3.0"
        "seal"
        "x-systemd.automount"
        "noauto"
        "x-systemd.device-timeout=5s"
        "x-systemd.mount-timeout=5s"
        "soft"
        "credentials=${config.clan.core.vars.generators.storagebox-immich-secret.files."credentials".path}"
        "uid=immich"
        "gid=immich"
      ];
    };
  };
}
