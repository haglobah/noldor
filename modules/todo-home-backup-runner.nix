{ inputs }:
{
  config,
  pkgs,
  ...
}:
let
  key = config.clan.core.vars.generators.todo-home-backup-transport.files.key.path;
  ssh = "${pkgs.openssh}/bin/ssh -i ${key} -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20";
  signal = status: ''printf '%s\n' ${status} | ${ssh} root@49.12.12.164'';
in
{
  imports = [
    inputs.ht.nixosModules.backup-test
    ./todo-home-backup-key.nix
  ];
  programs.ssh.knownHosts = {
    todo-backup-orthanc = {
      hostNames = [ "[91.99.217.220]:443" ];
      publicKey = builtins.readFile ../vars/per-machine/orthanc/openssh/ssh.id_ed25519.pub/value;
    };
    todo-backup-formenos = {
      hostNames = [ "49.12.12.164" ];
      publicKey = builtins.readFile ../vars/per-machine/formenos/openssh/ssh.id_ed25519.pub/value;
    };
  };
  services.todo-home-backup-test = {
    enable = true;
    driver = inputs.ht.packages.${pkgs.stdenv.hostPlatform.system}.backup-test-driver;
    onCalendar = "*-*-* 04:00:00 UTC";
    maxBackupAgeSeconds = 93600;
    fetchCommand = ''
      transport="$(dirname "$BACKUP_ARCHIVE")/transport.tar"
      ${ssh} -p 443 root@91.99.217.220 > "$transport"
      ${pkgs.python3}/bin/python3 - "$transport" <<'PY'
      import os,sys,tarfile,shutil
      targets={'backup.tar': os.environ['BACKUP_ARCHIVE'], 'metadata.json': os.environ['BACKUP_METADATA']}
      with tarfile.open(sys.argv[1]) as source:
          members=source.getmembers()
          assert len(members)==2 and {m.name for m in members}==set(targets), 'Unexpected transport members'
          assert all(m.isfile() for m in members), 'Transport contains nonregular files'
          for m in members:
              with source.extractfile(m) as src, open(targets[m.name], 'xb') as dst:
                  shutil.copyfileobj(src, dst)
      PY
    '';
    successCommand = signal "success";
    notifyFailureCommand = signal "failure";
  };
}
