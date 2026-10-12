# difftastic from haglobah/difftastic's faster-graph-search branch: the
# same diffs, about 2-3x faster on large files (huge pages for the heap,
# a leaner graph search, changed sections searched in parallel).
#
# Reuses nixpkgs' derivation with the branch as src. The branch is based
# on the release nixpkgs packages, so the version stays the same and the
# `--version` install check still holds.
{
  difftastic,
  difftastic-src,
  rustPlatform,
}:
difftastic.overrideAttrs (old: {
  src = difftastic-src;
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${difftastic-src}/Cargo.lock";
  };
})
