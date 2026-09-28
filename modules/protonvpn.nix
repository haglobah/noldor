# ProtonVPN as a NetworkManager WireGuard profile named "ProtonVPN".
#
# GNOME shows it as a VPN toggle in quick settings and a lock icon in the
# top bar while it is up; home/modules/protonvpn.nix binds a toggle key.
# WireGuard is UDP only, so it fails on networks that block UDP (the school
# FortiGate). Use the Proton app with the Stealth protocol there.
# While it is up, IPv6 outside the tunnel is rejected (see ipv6-block.sh).
#
# Setup: download a WireGuard config for Linux from
# https://account.protonvpn.com/downloads, then
#   clan vars generate gondor --generator protonvpn
# and paste the file. To switch servers, rerun with --regenerate, deploy,
# and `systemctl restart protonvpn-profile`.
{ config, pkgs, ... }:
let
  profile = config.clan.core.vars.generators.protonvpn.files."ProtonVPN.nmconnection";
in
{
  clan.core.vars.generators.protonvpn = {
    files."ProtonVPN.nmconnection" = { };
    prompts."wireguard-config" = {
      type = "multiline-hidden";
      description = "Proton WireGuard config file (wg-quick format), pasted whole";
    };
    runtimeInputs = [
      pkgs.bash
      pkgs.gnused
      pkgs.gnugrep
    ];
    script = ''
      bash ${./protonvpn/wg-to-nmconnection.sh} \
        < "$prompts/wireguard-config" > "$out/ProtonVPN.nmconnection"
    '';
  };

  # Same mechanism as networking.networkmanager.ensureProfiles: profiles in
  # /run are declarative and vanish on reboot, until this unit runs again.
  # ensureProfiles itself can't express the optional IPv6 section.
  systemd.services.protonvpn-profile = {
    description = "Install the ProtonVPN NetworkManager profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    requires = [ "NetworkManager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -D -m 0600 ${profile.path} /run/NetworkManager/system-connections/ProtonVPN.nmconnection
      ${pkgs.networkmanager}/bin/nmcli connection reload
    '';
  };

  # Proton's config is IPv4 only: block IPv6 outside the tunnel while it's up.
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "protonvpn-ipv6-block" ''
        PATH=${pkgs.nftables}/bin:$PATH
        ${builtins.readFile ./protonvpn/ipv6-block.sh}
      '';
    }
  ];

  # NetworkManager routes the full tunnel with policy routing; a strict
  # reverse path filter would drop the replies.
  networking.firewall.checkReversePath = "loose";
}
