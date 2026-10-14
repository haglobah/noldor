# Shared clan vars of the on-demand build machine aule: imported by aule
# (./nix-builder.nix) and by gondor (./nix-builder-client.nix). See
# docs/nix-builder.md.
{ lib, pkgs, ... }:
{
  clan.core.vars.generators = {
    # Hetzner Cloud API token (Read & Write). gondor creates and deletes
    # aule with it, aule deletes itself. ./nix-builder-client.nix makes it
    # readable for beat on gondor.
    hcloud-token = {
      share = true;
      files.token = { };
      prompts.token = {
        type = "hidden";
        description = "Hetzner Cloud API token (project of aule, Read & Write)";
      };
      script = ''tr -d '[:space:]' < "$prompts/token" > "$out/token"'';
    };

    # gondor's nix-daemon logs in to aule's nix-ssh user with this key.
    # Only gondor gets the private half; aule reads the public half at eval.
    nix-builder-ssh = {
      share = true;
      files.id_ed25519.deploy = lib.mkDefault false;
      files."id_ed25519.pub".secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C "nix-daemon@gondor" -f "$out/id_ed25519"
      '';
    };
  };
}
