{
  lib,
  runCommand,
  makeWrapper,
  python3,
  glib,
  mutter,
  libnotify,
}:
let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
in
runCommand "screen-above"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.mainProgram = "screen-above";
  }
  ''
    install -Dm644 ${./screen_above.py} $out/lib/screen_above.py
    makeWrapper ${python}/bin/python3 $out/bin/screen-above \
      --add-flags $out/lib/screen_above.py \
      --prefix GI_TYPELIB_PATH : ${lib.getLib glib}/lib/girepository-1.0 \
      --prefix PATH : ${
        lib.makeBinPath [
          mutter
          libnotify
        ]
      }
  ''
