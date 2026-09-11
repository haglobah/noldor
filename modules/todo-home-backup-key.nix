# Dedicated transport identity, restricted to fixed commands on receivers.
{ config, pkgs, ... }: {
  clan.core.vars.generators.todo-home-backup-transport = {
    share = true;
    files.key.deploy = config.networking.hostName == "gondor";
    files."key.pub".secret = false;
    runtimeInputs = [ pkgs.openssh ];
    script = ''ssh-keygen -q -t ed25519 -N "" -C todo-home-backup-test -f "$out/key"'';
  };
}
