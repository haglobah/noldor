# Bombadil (Antithesis' property-based testing for web UIs) from its latest
# GitHub release; nixpkgs doesn't package it.
#
# One unpinned flake input that `nix flake update` re-locks:
#   bombadil-bin  the `releases/latest/download/bombadil-x86_64-linux` binary
#
# Upstream ships a static-pie binary, so it runs as is. The release carries no
# version file, so the derivation name has none; `bombadil --version` has it.
# CHROME points at nixpkgs' chromium unless already set: Bombadil otherwise
# searches PATH and FHS paths for a browser.
{
  lib,
  stdenvNoCC,
  bombadil-bin,
  chromium,
  makeBinaryWrapper,
}:
assert lib.assertMsg (
  stdenvNoCC.hostPlatform.system == "x86_64-linux"
) "bombadil-bin is the x86_64-linux binary; add a flake input for ${stdenvNoCC.hostPlatform.system}";
stdenvNoCC.mkDerivation {
  name = "bombadil";
  src = bombadil-bin;
  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  # Upstream ships stripped static-pie binaries.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/libexec/bombadil
    makeWrapper $out/libexec/bombadil $out/bin/bombadil \
      --set-default CHROME ${lib.getExe chromium}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/bombadil --version
    runHook postInstallCheck
  '';

  meta = {
    description = "Property-based testing for web UIs";
    homepage = "https://github.com/antithesishq/bombadil";
    mainProgram = "bombadil";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
