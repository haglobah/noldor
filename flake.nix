{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    nixpkgs-24-11.url = "github:nixos/nixpkgs?ref=nixos-24.11";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    alles = {
      url = "github:haglobah/alles";
    };

    nix-starter-kit = {
      url = "github:active-group/nix-starter-kit";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vimium-options.url = "github:uimataso/vimium-nixos";
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
          # # Import home-manager at the clan level
          # extraModules = [
          #   inputs.home-manager.nixosModules.home-manager
          # ];
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
            # _module.args.pkgs = import self.inputs.nixpkgs {
            #   inherit system;
            #   config.allowUnfree = true;
            # };
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.nixfmt-rfc-style
                clan-core.packages.${system}.clan-cli
              ];
            };
          };
      }
    );
}
