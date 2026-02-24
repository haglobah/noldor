{ config, pkgs, ... }:
{
  config = {
    services.openclaw-agent = {
      enable = true;
      envFile = "/var/lib/openclaw-agent/.env";
    };
  };
}
