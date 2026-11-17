# difftastic from haglobah/difftastic's faster-graph-search branch: the
# same diffs, about 2-3x faster on large files (huge pages for the heap,
# a leaner graph search, changed sections searched in parallel).
#
# Reuses nixpkgs' derivation with the branch as src. The version comes
# from the branch's Cargo.toml, so the `--version` install check holds
# even when nixpkgs moves to a newer release than the branch is based on.
{
  lib,
  difftastic,
  difftastic-src,
  rustPlatform,
}:
difftastic.overrideAttrs (old: {
  version = (lib.importTOML "${difftastic-src}/Cargo.toml").package.version;
  src = difftastic-src;
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${difftastic-src}/Cargo.lock";
  };
})
