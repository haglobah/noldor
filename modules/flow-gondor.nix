# hotlustre on gondor: the laptop instance, kept on one version graph with
# cirdan's (./flow.nix; hotlustre's core/sync.ts and ADR-002). It runs as
# beat from the checkout on 127.0.0.1:8040, without sign-in, and its agent
# uses the claude login in the app's own config dir (`bin/hotlustre
# login`). gondor can reach cirdan but not the other way round, so this
# instance fetches and pushes; cirdan merges when the two diverged.
# Needs inputs.hotlustre.nixosModules.default, imported in clan.nix.
{ config, ... }:
let
  checkout = "/home/beat/projects/hotlustre";
in
{
  services.hotlustre = {
    enable = true;
    user = "beat";
    inherit checkout;
    dataDir = "${checkout}/data";
    # The agent's shell gets the tools of Beat's own shell, as when the core
    # ran in his terminal.
    extraPackages = [
      config.system.path
      config.home-manager.users.beat.home.path
    ];
    sync = {
      instance = "gondor";
      # cirdan's address from the clan inventory; its sshd is behind sslh on 443.
      peer = "cirdan=ssh://beat@2.29.126.128:443${checkout}/data/core/repo.git";
    };
  };
}
