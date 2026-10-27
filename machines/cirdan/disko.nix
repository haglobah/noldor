# ---
# schema = "single-disk"
# [placeholders]
# mainDisk = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_131521962" 
# ---
# This file was automatically generated!
# CHANGING this configuration requires wiping and reinstalling the machine
{

  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  disko.devices = {
    disk = {
      main = {
        name = "main-a208afa97e4142e26046a07794597c12";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_131521962";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            "boot" = {
              size = "1M";
              type = "EF02"; # for grub MBR
              priority = 1;
            };
            # Kernel device nodes, not by-partlabel: on the installer udev
            # creates the partlabel links too late for mkfs (2026-10-27).
            ESP = {
              device = "/dev/sda2";
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              device = "/dev/sda3";
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
