{ pkgs, ... }:
let
  screen-above = pkgs.callPackage ../pkgs/screen-above { };
  prefix = "org/gnome/settings-daemon/plugins/media-keys";
in
{
  home.packages = [ screen-above ];
  dconf.settings = {
    # GNOME places a new screen right of the laptop. Ctrl+Super+Up moves the
    # one external screen above the laptop, centered, and GNOME remembers it.
    "${prefix}".custom-keybindings = [ "/${prefix}/custom-keybindings/screen-above/" ];
    "${prefix}/custom-keybindings/screen-above" = {
      name = "Place external screen above laptop";
      binding = "<Control><Super>Up";
      command = "${screen-above}/bin/screen-above";
    };
  };
}
