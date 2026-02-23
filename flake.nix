{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    nixpkgs-24-11.url = "github:nixos/nixpkgs?ref=nixos-24.11";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    clan-core = {
      url = "https://git.clan.lol/haglobah/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    nix-starter-kit = {
      url = "github:active-group/nix-starter-kit";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    vimium-options.url = "github:uimataso/vimium-nixos";

    alles.url = "github:haglobah/alles";
    gastown.url = "github:steveyegge/gastown";
    nix-openclaw.url = "github:openclaw/nix-openclaw";
  };

  outputs =
    {
      clan-core,
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
          _module.args = { inherit inputs; };
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
