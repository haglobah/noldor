{ pkgs, ... }:
{
  # Can be imported into machines to enable GNOME and GDM.
  #
  # Copy this into a machine's configuration:
  # `machines/<name>/configuration.nix`
  # ```nix
  # imports = [
  #   ../../modules/gnome.nix
  # ];
  # ```

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  systemd.user.services.ibus-restart = {
    description = "Restart ibus daemon";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ibus}/bin/ibus restart";
    };
  };

  systemd.user.timers.ibus-restart = {
    description = "Regularly restart ibus daemon";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
  };
}
