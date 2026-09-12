{ pkgs, ... }:
let
  brightness = pkgs.callPackage ../pkgs/monitor-brightness { };
  prefix = "org/gnome/settings-daemon/plugins/media-keys";
in
{
  home.packages = [ brightness ];
  dconf.settings = {
    # ZMK rae_dux NAV already emits C_BRI_DN / C_BRI_UP (top row,
    # left-hand positions 1 and 4). Add Ctrl+Super shortcuts while preserving
    # GNOME's existing brightness and Shift+brightness bindings.
    "${prefix}".custom-keybindings = [
      "/${prefix}/custom-keybindings/monitor-brightness-up/"
      "/${prefix}/custom-keybindings/monitor-brightness-down/"
    ];
    "${prefix}/custom-keybindings/monitor-brightness-up" = {
      name = "Increase external monitor brightness";
      binding = "<Control><Super>XF86MonBrightnessUp";
      command = "${brightness}/bin/monitor-brightness up";
    };
    "${prefix}/custom-keybindings/monitor-brightness-down" = {
      name = "Decrease external monitor brightness";
      binding = "<Control><Super>XF86MonBrightnessDown";
      command = "${brightness}/bin/monitor-brightness down";
    };
  };
}
