{
  imports = [

  ];

  # Scripted initrd is deprecated, removal scheduled for NixOS 26.11.
  # Only takes effect at the next reboot — verify the box comes back up.
  boot.initrd.systemd.enable = true;
}
