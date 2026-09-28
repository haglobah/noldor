{ pkgs, ... }:
let
  toggle = pkgs.writeShellApplication {
    name = "protonvpn-toggle";
    runtimeInputs = [
      pkgs.networkmanager
      pkgs.gnugrep
      pkgs.libnotify
    ];
    text = builtins.readFile ./protonvpn-toggle.sh;
  };
  prefix = "org/gnome/settings-daemon/plugins/media-keys";
in
{
  # The NetworkManager "ProtonVPN" profile comes from modules/protonvpn.nix.
  # The Proton app is for networks that block UDP: its Stealth protocol
  # runs over TCP. Its tray icon needs the AppIndicator extension.
  home.packages = [
    toggle
    pkgs.proton-vpn
    pkgs.gnomeExtensions.appindicator
  ];

  dconf.settings = {
    "org/gnome/shell".enabled-extensions = [ "appindicatorsupport@rgcjonas.gmail.com" ];

    "${prefix}".custom-keybindings = [ "/${prefix}/custom-keybindings/protonvpn-toggle/" ];
    "${prefix}/custom-keybindings/protonvpn-toggle" = {
      name = "Toggle ProtonVPN";
      binding = "<Shift><Super>v";
      command = "${toggle}/bin/protonvpn-toggle";
    };
  };
}
