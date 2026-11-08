# `clan ssh` abbreviations for every clan machine, from any directory:
# cs<m> opens fish as root on machine <m>, cs<m><u> a login shell as its
# normal user <u> (`m` and `u` being first letters). Only for gondor, where
# the clan lives in ~/noldor.
{ inputs, lib, ... }:
let
  clanSsh = "clan ssh --flake ~/noldor";

  # Throws when two names share a first letter, so no abbreviation silently
  # shadows another.
  byInitial =
    what: names:
    let
      grouped = lib.groupBy (lib.substring 0 1) names;
      clashes = lib.filterAttrs (_: ns: lib.length ns > 1) grouped;
    in
    if clashes == { } then
      lib.mapAttrs (_: lib.head) grouped
    else
      throw "clan-ssh.nix: ${what} share a first letter: ${
        lib.concatMapStringsSep "; " (lib.concatStringsSep ", ") (lib.attrValues clashes)
      }";

  machines = inputs.self.nixosConfigurations;

  abbrsFor =
    m: machine:
    let
      users = lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser) machines.${machine}.config.users.users);
    in
    {
      "cs${m}" = "${clanSsh} ${machine} -c fish";
    }
    // lib.mapAttrs' (
      u: user: lib.nameValuePair "cs${m}${u}" "${clanSsh} ${machine} -c sudo -iu ${user}"
    ) (byInitial "users on ${machine}" users);
in
{
  programs.fish.shellAbbrs = {
    "cs" = clanSsh;
  }
  // lib.concatMapAttrs abbrsFor (byInitial "clan machines" (lib.attrNames machines));
}
