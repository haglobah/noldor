# Test of flow-backup (modules/flow-backup.nix) against local bare "GitHub"
# repositories, with a fake curl that logs what it would post. The cases
# are in ./flow-backup.sh.
{ pkgs }:
let
  fakeCurl = pkgs.writeShellScriptBin "curl" ''
    printf '%s\n' "$*" | tr '\n' ' ' >>"$CURL_LOG"
    echo >>"$CURL_LOG"
  '';
  backup = pkgs.callPackage ../modules/flow-backup.nix { curl = fakeCurl; };
in
pkgs.runCommand "flow-backup"
  {
    nativeBuildInputs = [
      backup
      pkgs.git
    ];
  }
  ''
    export HOME=$TMPDIR
    bash ${./flow-backup.sh}
    touch $out
  ''
