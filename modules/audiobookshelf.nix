{ config, pkgs, ... }:
{
  services.audiobookshelf = {
    enable = true;
  };

  services.caddy = {
    enable = true;
    virtualHosts."books.hagenlocher.me" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${config.services.audiobookshelf.port}
      '';
    };
  };
}
