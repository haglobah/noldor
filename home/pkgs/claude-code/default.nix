# Claude Code from its latest GitHub release, ahead of nixpkgs.
#
# Two unpinned flake inputs that `nix flake update` re-locks:
#   claude-code-version  Anthropic's `latest` version file (one line)
#   claude-code-bin      the `releases/latest/download/…` tarball
#
# When nixpkgs has caught up (its version >= the release), we return the
# nixpkgs derivation unchanged and get its cached build. Otherwise we reuse
# it (wrapper, autoPatchelf, `--version` install check) with the release
# binary as src. A version mismatch between the two inputs fails the
# `--version` check, so it cannot go unnoticed.
{
  lib,
  stdenv,
  claude-code,
  claude-code-bin,
  claude-code-version,
  releaseVersion ? lib.fileContents claude-code-version,
}:
let
  platformKey = "${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}";
in
assert lib.assertMsg (
  platformKey == "linux-x64"
) "claude-code-bin is the linux-x64 release; add a flake input for ${platformKey}";
if lib.versionAtLeast claude-code.version releaseVersion then
  claude-code
else
  claude-code.overrideAttrs (
    old:
    assert lib.assertMsg (lib.hasInfix "installBin $src" old.installPhase)
      "nixpkgs' claude-code installPhase changed; update this override";
    {
      version = releaseVersion;
      # The flake input is the unpacked tarball: a directory holding `claude`.
      src = claude-code-bin;
      installPhase =
        builtins.replaceStrings [ "installBin $src" ] [ "installBin $src/claude" ]
          old.installPhase;
    }
  )
