{ ... }:
{
  # catppuccin/nix builds whiskers + all themed ports from its own package set,
  # so cache.nixos.org never has them. This is the cache their CI pushes to
  # (same values as the flake's opt-in catppuccin.cache.enable option).
  nix.settings = {
    extra-substituters = [ "https://catppuccin.cachix.org" ];
    extra-trusted-public-keys = [
      "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
    ];
  };
}
