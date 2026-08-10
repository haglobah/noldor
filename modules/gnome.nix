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

  # gnome-shell acts as ibus's panel (the daemon runs with --panel disable),
  # and at login the panel/extension registration races against ibus-daemon
  # startup, leaving unicode input (Ctrl+Shift+U) dead until the daemon is
  # restarted once. Restarting the unit after the session is up re-runs the
  # registration with gnome-shell fully initialized.
  systemd.user.services.ibus-restart = {
    description = "Restart the IBus daemon once the GNOME session is up";
    wantedBy = [ "gnome-session.target" ];
    after = [
      "gnome-session.target"
      "org.freedesktop.IBus.session.GNOME.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      # Margin for gnome-shell's IBus manager to finish connecting, so the
      # restart lands after the racy first registration, not inside it.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user restart org.freedesktop.IBus.session.GNOME.service";
    };
  };
}
