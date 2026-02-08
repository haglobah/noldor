{
  config = {
    services.caddy = {
      enable = true;
      virtualHosts."paperless.hagenlocher.me" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:28981
        '';
      };
    };
    # https://docs.clan.lol/guides/backups/backup-intro/
    clan.core.state.paperless = {
      folders = [
        "/var/lib/paperless"
      ];
    };
    # https://wiki.nixos.org/wiki/Paperless-ngx
    services.paperless = {
      enable = true;
      consumptionDirIsPublic = true;
      settings = {
        PAPERLESS_CONSUMER_IGNORE_PATTERN = [
          ".DS_STORE/*"
          "desktop.ini"
        ];
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        PAPERLESS_OCR_USER_ARGS = {
          optimize = 1;
          pdfa_image_compression = "lossless";
        };
        PAPERLESS_URL = "https://paperless.hagenlocher.me";
      };
    };
  };
}
