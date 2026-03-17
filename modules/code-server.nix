{ config, pkgs, ... }:
{
  config = {
    services.caddy = {
      enable = true;
      virtualHosts."code.hagenlocher.me" = {
        # Needs 'localhost' not 127.0.0.1 since it runs on ipv6?
        extraConfig = ''
          reverse_proxy localhost:4444
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
