# Lets aule copy closures it built for this machine onto it
# (../machines/aule/deploys.nix): its deploy key may only speak the
# nix-daemon protocol, which `nix copy --to ssh-ng://` uses. No shell,
# no forwarding, no activation.
{ config, lib, ... }:
let
  pub = ../vars/per-machine/aule/aule-deploy-ssh/id_ed25519.pub/value;
in
{
  users.users.root.openssh.authorizedKeys.keys = lib.optional (builtins.pathExists pub) ''restrict,command="${config.nix.package}/bin/nix-daemon --stdio" ${lib.fileContents pub}'';
}
