{ pkgs, ... }:
let
  pname = "donethat";
  version = "2.2.5";

  src = pkgs.fetchurl {
    url = "https://github.com/donethatai/donethat-releases/releases/download/v${version}/DoneThat-x86_64.AppImage";
    sha256 = "sha256:e5b2992999a9f7e260967d767d04018f02146772819af084c24550bf3aed8ad7";
  };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;
  pkgs = pkgs;
  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${appimageContents}/usr/share/icons $out/share

    # unless linked, the binary is placed in $out/bin/donethat-someVersion
    # ln -s $out/bin/${pname}-${version} $out/bin/${pname}
  '';

  # extraBwrapArgs = [
  #   "--bind-try /etc/nixos/ /etc/nixos/"
  # ];

  # vscode likes to kill the parent so that the
  # gui application isn't attached to the terminal session
  # dieWithParent = false;

  # extraPkgs =
  #   pkgs: with pkgs; [
  #     unzip
  #     autoPatchelfHook
  #     asar
  #     # override doesn't preserve splicing https://github.com/NixOS/nixpkgs/issues/132651
  #     (buildPackages.wrapGAppsHook.override { inherit (buildPackages) makeWrapper; })
  #   ];
}
