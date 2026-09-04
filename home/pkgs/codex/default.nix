# Codex from its latest GitHub release, ahead of nixpkgs.
#
# One unpinned flake input that `nix flake update` re-locks:
#   codex-bin  the `releases/latest/download/codex-package-…` bundle
#
# The bundle names its own version in codex-package.json, so there is no
# separate version input. When nixpkgs has caught up (its version >= the
# release), we return the nixpkgs derivation unchanged and get its cached
# build. Otherwise we build a small binary derivation that mirrors what
# nixpkgs does after its Rust build: install `codex` and its
# `codex-code-mode-host` companion, prefix PATH with ripgrep and bubblewrap,
# install shell completions, and check `--version` against the version.
{
  lib,
  stdenvNoCC,
  bubblewrap,
  codex,
  codex-bin,
  installShellFiles,
  makeBinaryWrapper,
  ripgrep,
  versionCheckHook,
  bundle ? builtins.fromJSON (builtins.readFile "${codex-bin}/codex-package.json"),
  releaseVersion ? bundle.version,
}:
assert lib.assertMsg (
  stdenvNoCC.hostPlatform.system == "x86_64-linux"
) "codex-bin is the x86_64-linux bundle; add a flake input for ${stdenvNoCC.hostPlatform.system}";
assert lib.assertMsg (bundle.layoutVersion == 1)
  "codex-package.json layoutVersion changed to ${toString bundle.layoutVersion}; update this package";
if lib.versionAtLeast codex.version releaseVersion then
  codex
else
  stdenvNoCC.mkDerivation {
    pname = "codex";
    version = releaseVersion;
    src = codex-bin;

    nativeBuildInputs = [
      installShellFiles
      makeBinaryWrapper
    ];

    # Upstream ships stripped static-pie binaries.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      installBin ${bundle.entrypoint} bin/codex-code-mode-host
      runHook postInstall
    '';

    postInstall = ''
      installShellCompletion --cmd codex \
        --bash <($out/bin/codex completion bash) \
        --fish <($out/bin/codex completion fish) \
        --zsh <($out/bin/codex completion zsh)
    '';

    postFixup = ''
      wrapProgram $out/bin/codex --prefix PATH : ${
        lib.makeBinPath [
          ripgrep
          bubblewrap
        ]
      }
    '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [ versionCheckHook ];

    meta = codex.meta // {
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
