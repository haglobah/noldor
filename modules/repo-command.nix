# `repo NAME`: Beat's repository NAME in ~/projects, cloned from
# github.com/haglobah the first time, its path printed. On cirdan the
# repositories are cloned only when needed (./flow.nix); hotlustre's agent
# is told to use it on both machines.
{ lib, pkgs, ... }:
let
  repo = pkgs.writeShellApplication {
    name = "repo";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    # Existing clones are left alone: they may hold work.
    text = ''
      name=''${1:?usage: repo NAME (a repository of github.com/haglobah)}
      dir=$HOME/projects/$name
      [ -d "$dir" ] || git clone --quiet "git@github.com:haglobah/$name.git" "$dir" >&2
      echo "$dir"
    '';
  };
in
{
  options.programs.repo.package = lib.mkOption {
    type = lib.types.package;
    default = repo;
    readOnly = true;
  };
  config.environment.systemPackages = [ repo ];
}
