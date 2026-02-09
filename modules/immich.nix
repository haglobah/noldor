{ config, pkgs, ... }:
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
      # machine-learning.enable = false;
      openFirewall = true;
    };

    # systemd.services.immich-server = {
    #   serviceConfig = {
    #     Restart = "always";
    #     RestartSec = 10;
    #   };
    # };

    environment.systemPackages = [ pkgs.cifs-utils ];
    fileSystems."/var/lib/immich" = {
      device = "//u366465-sub7.your-storagebox.de/u366465-sub7";
      fsType = "cifs";
      options = [
        "x-systemd.automount"
        "noauto"
        "x-systemd.device-timeout=5s"
        "x-systemd.mount-timeout=5s"
        "credentials=${config.clan.core.vars.generators.storagebox-immich-secret.files."credentials".path}"
        "uid=immich"
        "gid=immich"
      ];
    };
  };
}
