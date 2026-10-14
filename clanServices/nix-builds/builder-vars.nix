# Vars of the on-demand builder, shared by roles `builder` (aule),
# `scheduler` (orthanc) and the operator CLI on gondor (../../modules/nix-builder-operator.nix).
{ lib, pkgs, ... }:
{
  clan.core.vars.generators = {
    # Hetzner Cloud API token (Read & Write). The scheduler creates aule,
    # aule deletes itself, gondor refreshes the snapshot.
    hcloud-token = {
      share = true;
      files.token = { };
      prompts.token = {
        type = "hidden";
        description = "Hetzner Cloud API token (project of aule, Read & Write)";
      };
      script = ''tr -d '[:space:]' < "$prompts/token" > "$out/token"'';
    };

    # The scheduler's nix logs in to aule's nix-ssh user with this key. Only
    # the scheduler gets the private half; aule reads the public half at eval.
    nix-builds-ssh = {
      share = true;
      files.id_ed25519.deploy = lib.mkDefault false;
      files."id_ed25519.pub".secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C "nix-builds-scheduler" -f "$out/id_ed25519"
      '';
    };
  };
}
