{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs =
    {
      self,
      clan-core,
      nixpkgs,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, pkgs, ... }:
      {
        imports = [
          inputs.clan-core.flakeModules.default
        ];

        systems = [
          "x86_64-linux"
        ];

        clan = {
          imports = [
            ./clan.nix
          ];
        };

        perSystem =
          {
            config,
            system,
            self',
            pkgs,
            ...
          }:
          {
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.nixfmt
                clan-core.packages.${system}.clan-cli
                pkgs.kanidm_1_8
              ];

              shellHook = ''
                export KANIDM_URL=https://idm.hagenlocher.me
              '';
            };
          };
      }
    );
}
