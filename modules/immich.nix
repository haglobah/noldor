{ config, ... }:
{
  config = {
    services.immich = {
      enable = true;
      host = "photos.hagenlocher.me";
    };
  };

  # Mount for storage box
  fileSystems."/mnt/share" = {
    device = "//u366465-sub7.your-storagebox.de\u366465-sub7";
    fsType = "cifs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "credentials=${config.clan.core.vars.generators.storagebox-immich-secret.files."credentials".path}"
      "uid=1000"
      "gid=100"
    ];
  };
}
