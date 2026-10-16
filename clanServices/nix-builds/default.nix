# nix-builds: repos that install Beat's GitHub App and declare
# `buildJobs.<system>` in their flake get those outputs built, signed and
# pushed to the private R2 cache, on an on-demand Hetzner machine that only
# exists (and bills) while there is something to build. See ./README.md.
{ ... }:
let
  # Each role reads the other roles' public vars from the repo, so it needs
  # their machine names. Secrets stay per machine: clan requires a shared
  # generator to be declared alike everywhere, deploy flag included.
  one =
    role: roles:
    let
      ms = builtins.attrNames (roles.${role}.machines or { });
    in
    if builtins.length ms == 1 then
      builtins.head ms
    else
      throw "nix-builds: exactly one machine needs the ${role} role, found ${toString ms}";
  names = roles: {
    nixBuilds.builderName = one "builder" roles;
    nixBuilds.schedulerName = one "scheduler" roles;
  };
in
{
  _class = "clan.service";
  manifest.name = "@beat/nix-builds";
  manifest.description = "Builds registered repos on an on-demand machine into a private R2 cache";
  manifest.categories = [ "System" ];
  manifest.readme = builtins.readFile ./README.md;

  roles.client = {
    description = "Substitutes from the R2 cache and trusts its signing keys";
    perInstance =
      { roles, ... }:
      {
        nixosModule = {
          imports = [ ./client.nix ];
          config = names roles;
        };
      };
  };

  roles.builder = {
    description = "The on-demand build machine; signs and pushes what it builds (aule)";
    perInstance =
      { roles, ... }:
      {
        nixosModule = {
          imports = [ ./builder.nix ];
          config = names roles;
        };
      };
  };

  roles.scheduler = {
    description = "Watches the GitHub App's repos and runs builds on the builder (orthanc)";
    interface =
      { lib, ... }:
      {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            example = "builds.example.org";
            description = "Public host for the GitHub webhook (Caddy vhost).";
          };
          tagPattern = lib.mkOption {
            type = lib.types.str;
            default = "v*";
            description = "Tags that get built, next to the default branch.";
          };
          pollInterval = lib.mkOption {
            type = lib.types.ints.positive;
            default = 300;
            description = "Seconds between polls, the backup for missed webhooks.";
          };
          hetzner.types = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            # CX53: 16 shared vCPU, 32 GB, often sold out. CCX33: 8
            # dedicated vCPU, 32 GB, ~4.7x the price per hour.
            default = [
              "cx53"
              "ccx33"
            ];
            description = "Server types to try, in order.";
          };
          hetzner.locations = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "fsn1"
              "nbg1"
            ];
            description = "Locations to try for each type, in order.";
          };
          ntfyGenerator = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "updater-alerts";
            description = "A vars generator with an `env_file` holding NTFY_TOPIC=; failures post there.";
          };
        };
      };
    perInstance =
      { settings, roles, ... }:
      {
        nixosModule = {
          imports = [ (import ./scheduler.nix { inherit settings; }) ];
          config = names roles;
        };
      };
  };
}
