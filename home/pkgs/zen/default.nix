# Zen mode GNOME Shell extension; see extension/extension.js.
{ stdenvNoCC, glib }:
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-zen";
  version = "1";
  src = ./extension;
  nativeBuildInputs = [ glib ];
  installPhase = ''
    dir=$out/share/gnome-shell/extensions/zen@noldor
    mkdir -p $dir
    cp -r . $dir
    glib-compile-schemas $dir/schemas
  '';
  passthru.extensionUuid = "zen@noldor";
}
