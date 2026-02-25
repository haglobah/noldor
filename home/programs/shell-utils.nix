{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    wget
    curl
    traceroute
    dnsutils
    jq
    tmux
    cachix
    dua
    gnupg
    pass
    nix-output-monitor
  ];

  programs.direnv = {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };

  programs.btop = {
    enable = true;
  };
  programs.bat = {
    enable = true;
  };
  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    git = true;
  };
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
  };
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
  };
  programs.broot = {
    enable = true;
  };
}
