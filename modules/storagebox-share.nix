# The Storage Box mounted over SFTP on port 23. CIFS needs port 445,
# which many networks block outbound; SSH on 23 gets through.
#
# The public key must be installed on the Storage Box once:
#   cat vars/per-machine/gondor/storagebox-share-ssh/key.pub/value \
#     | ssh -p 23 u366465@u366465.your-storagebox.de install-ssh-key
{ config, pkgs, ... }:
let
  host = "u366465.your-storagebox.de";
  key = config.clan.core.vars.generators.storagebox-share-ssh.files.key.path;
in
{
  clan.core.vars.generators.storagebox-share-ssh = {
    files.key = { };
    files."key.pub".secret = false;
    runtimeInputs = [ pkgs.openssh ];
    script = ''ssh-keygen -q -t ed25519 -N "" -C storagebox-share -f "$out/key"'';
  };

  # Matches the ED25519 fingerprint Hetzner publishes for Storage Boxes:
  # SHA256:XqONwb1S0zuj5A1CDxpOSuD2hnAArV1A3wKY7Z3sdgM
  programs.ssh.knownHosts.storagebox = {
    hostNames = [ "[${host}]:23" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
  };

  fileSystems."/mnt/share" = {
    # Empty path: the login directory, the same tree as the old "backup" SMB share.
    device = "u366465@${host}:";
    fsType = "sshfs";
    noCheck = true;
    options = [
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "x-systemd.idle-timeout=60"
      # SSH needs longer than SMB did to connect and authenticate.
      "x-systemd.mount-timeout=15s"
      "port=23"
      "IdentityFile=${key}"
      "IdentitiesOnly=yes"
      "BatchMode=yes"
      "StrictHostKeyChecking=yes"
      "ConnectTimeout=10"
      "ServerAliveInterval=15"
      "reconnect"
      "allow_other"
      "uid=1000"
      "gid=100"
    ];
  };
}
