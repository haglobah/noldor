{ pkgs, ... }:
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
      # paperless-ngx 3.4.2 pins torch<2.15, nixpkgs ships 2.15.0 (2026-11-13);
      # its test suite still runs. Drop once nixpkgs relaxes it itself.
      # overrideAttrs, not overridePythonAttrs: the module calls .override on it.
      package = pkgs.paperless-ngx.overrideAttrs (old: {
        pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "torch" ];
      });
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
