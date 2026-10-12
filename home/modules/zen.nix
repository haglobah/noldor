# Zen mode: Super+Z blurs every window but the focused one, blocks window
# switching (including run-or-raise) and mutes notification banners.
# Ctrl+Alt+Super+Escape ends it, as does closing the window.
{ pkgs, ... }:
let
  zen = pkgs.callPackage ../pkgs/zen { };
in
{
  home.packages = [ zen ];
  dconf.settings."org/gnome/shell".enabled-extensions = [ zen.extensionUuid ];
}
