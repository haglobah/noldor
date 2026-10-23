{ pkgs, ... }:
let
  # uxplay -p pins its ports so the firewall can stay closed otherwise:
  # TCP 7000, 7001, 7100 and UDP 6000, 6001, 7011.
  airplay = pkgs.writeShellScriptBin "airplay" ''
    exec ${pkgs.uxplay}/bin/uxplay -p -n "$(hostname)" -nh "$@"
  '';
  # Venue Wi-Fi often isolates clients or drops mDNS, so the phone never
  # sees the receiver. A hotspot on the laptop is a network we control.
  # It takes over the only Wi-Fi radio: the laptop is offline meanwhile.
  airplay-hotspot = pkgs.writeShellScriptBin "airplay-hotspot" ''
    set -eu
    case "''${1:-up}" in
      up)
        nmcli dev wifi hotspot con-name airplay-hotspot ssid "$(hostname)-airplay"
        nmcli dev wifi show-password
        ;;
      down) nmcli con down airplay-hotspot ;;
      *) echo "usage: airplay-hotspot [up|down]" >&2; exit 2 ;;
    esac
  '';
in
{
  # AirPlay receivers are found over mDNS (Bonjour).
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };

  networking.firewall.allowedTCPPorts = [
    7000
    7001
    7100
  ];
  networking.firewall.allowedUDPPorts = [
    6000
    6001
    7011
  ];

  environment.systemPackages = [
    pkgs.uxplay
    airplay
    airplay-hotspot
  ];
}
