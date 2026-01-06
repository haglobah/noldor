{ config, pkgs, ... }:
{
  config = {
    networking.hostName = "gondor";
    clan.core.networking.targetHost = "gondor";

    boot.kernelParams = [ "ipv6.disable=1" ];

    networking.nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    networking.networkmanager.dns = "none";

    environment.systemPackages = [
    ];
  };
}
