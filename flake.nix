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

    # Latest Claude Code release; both are unpinned URLs that
    # `nix flake update` re-locks. See home/pkgs/claude-code.
    claude-code-version = {
      url = "file+https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest";
      flake = false;
    };
    claude-code-bin = {
      url = "https://github.com/anthropics/claude-code/releases/latest/download/claude-linux-x64.tar.gz";
      flake = false;
    };

    # nix-starter-kit = {
    #   url = "github:active-group/nix-starter-kit";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.home-manager.follows = "home-manager";
    # };

    vimium-options.url = "github:uimataso/vimium-nixos";

    alles.url = "github:haglobah/alles";
    gastown.url = "github:haglobah/gastown";
    beads.url = "github:haglobah/beads";
    hx.url = "github:haglobah/hx";
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    todo-home.url = "git+ssh://git@github.com/haglobah/todo-home.git";
    # No nixpkgs.follows: orca's pnpmDeps hash is pinned to its own locked
    # nixpkgs' pnpm, and matching locks let gondor reuse the built store path.
    orca.url = "git+ssh://git@github.com/haglobah/orca.git?ref=nix-flake";
    colab.url = "git+ssh://git@github.com/haglobah/colab.git?ref=noldor-deploy";
    # donethat.url = "git+ssh://git@github.com/haglobah/donethat-electron.git";
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
            # claude-code is unfree; flake-parts' default pkgs would refuse it.
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };

            packages.claude-code = pkgs.callPackage ./home/pkgs/claude-code {
              inherit (inputs) claude-code-bin claude-code-version;
            };

            # Eval-time test of the nixpkgs fallback: older release -> nixpkgs
            # as-is; newer release -> nixpkgs' derivation with the release src.
            checks.claude-code-fallback =
              let
                mk =
                  releaseVersion:
                  pkgs.callPackage ./home/pkgs/claude-code {
                    inherit (inputs) claude-code-bin claude-code-version;
                    inherit releaseVersion;
                  };
                older = mk "0.0.1";
                newer = mk "999.0.0";
              in
              assert older == pkgs.claude-code;
              assert newer.version == "999.0.0";
              assert newer.src == inputs.claude-code-bin;
              pkgs.runCommand "claude-code-fallback" { } "touch $out";

            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.just
                pkgs.nixfmt
                # needed for backup testing
                pkgs.borgbackup
                clan-core.packages.${system}.clan-cli
                pkgs.kanidm_1_11
              ];

              shellHook = ''
                export KANIDM_URL=https://idm.hagenlocher.me
              '';
            };
          };
      }
    );
}
