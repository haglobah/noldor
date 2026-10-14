# aule, the smith: on-demand Hetzner Cloud build machine for gondor.
# Created from a snapshot when needed, deletes itself when idle.
# See docs/nix-builder.md and ../../modules/nix-builder.nix.
{ lib, modulesPath, ... }:
{
  imports = [
    # virtio drivers for Hetzner's KVM guests. No facter.json on purpose:
    # the snapshot boots on CX53 (Intel or AMD) and CCX33 (AMD) alike.
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/nix-builder.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.systemd.enable = true;

  # The snapshot comes from a small bootstrap disk; servers made from it
  # have 240-320 GB. Grow the partition and the filesystem on boot.
  boot.growPartition = true;
  fileSystems."/".autoResize = true;

  # Headless build box: keep man pages and docs out of the snapshot.
  documentation.enable = lib.mkDefault false;
}
