# Disk housekeeping for the long-lived servers (formenos, orthanc). gondor
# cleans up with `nh clean`; aule's builder module sets its own limits.
{
  # Old generations pile up and the deploy needs old + new closures to
  # coexist during the switch. This also prunes the other profiles in
  # /nix/var/nix/profiles, such as links-worker's.
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;

  # Collect garbage during a build or copy once free space drops below
  # 2 GiB, instead of failing the deploy with a full disk.
  nix.settings = {
    min-free = 2 * 1024 * 1024 * 1024;
    max-free = 6 * 1024 * 1024 * 1024;
  };

  # Logs live in VictoriaLogs for 30 days; the local journal only has to
  # bridge a formenos outage while Vector is blocked (metrics-shipper.nix).
  services.journald.settings.Journal.SystemMaxUse = "1G";
}
