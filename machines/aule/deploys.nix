# aule as a deploy build host: `clan machines update <machine> --build-host
# root@aule` builds there, and clan then runs `nix copy --to ssh-ng://<target>`
# on aule as root. This key lets that copy in without Beat's forwarded agent.
# Each target authorizes it for nix-daemon only (../../modules/aule-deploys.nix),
# so aule can add store paths but never activate or log in; activation still
# goes over gondor's own connection.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Machines aule deploys to, by the address in their deploy.targetHost.
  targets = {
    formenos = "49.12.12.164";
  };
  hostKey = machine: lib.fileContents ../../vars/per-machine/${machine}/openssh/ssh.id_ed25519.pub/value;
in
{
  clan.core.vars.generators.aule-deploy-ssh = {
    files.id_ed25519 = { };
    files."id_ed25519.pub".secret = false;
    runtimeInputs = [ pkgs.openssh ];
    script = ''
      ssh-keygen -t ed25519 -N "" -C "aule-deploy" -f "$out/id_ed25519"
    '';
  };

  programs.ssh.extraConfig = lib.concatMapStrings (address: ''
    Host ${address}
      IdentityFile ${config.clan.core.vars.generators.aule-deploy-ssh.files.id_ed25519.path}
  '') (lib.attrValues targets);

  programs.ssh.knownHosts =
    lib.mapAttrs (machine: address: {
      hostNames = [ address ];
      publicKey = hostKey machine;
    }) targets
    // {
      # Without --upload-inputs, aule fetches the private git+ssh inputs itself (with Beat's
      # forwarded agent); GitHub's published key, as in ../../modules/flow.nix.
      "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
}
