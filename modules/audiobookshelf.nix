{ config, pkgs, ... }:
{
  services.audiobookshelf = {
    enable = true;
    # Default ffmpeg-full drags clang-lib, samba, flite etc. into the
    # closure (~1.3 GiB); headless ffmpeg transcodes audio just fine
    package = pkgs.audiobookshelf.override { ffmpeg-full = pkgs.ffmpeg-headless; };
  };

  services.caddy = {
    enable = true;
    virtualHosts."books.hagenlocher.me" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString config.services.audiobookshelf.port}
      '';
    };
  };
}
