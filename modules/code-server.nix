{ config, pkgs, ... }:
{
  config = {
    services.caddy = {
      enable = true;
      virtualHosts."code.hagenlocher.me" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:4444
        '';
      };
    };

    services.code-server = {
      enable = true;
      package = pkgs.vscode-with-extensions.override {
        vscode = pkgs.code-server;
        vscodeExtensions = with pkgs.vscode-extensions; [
          bbenoist.nix
          dracula-theme.theme-dracula
          elixir-lsp.vscode-elixir-ls
        ];
      };
      extraPackages = with pkgs; [
        git
        beamMinimal28Packages.elixir_1_19
      ];
    };
  };
}
