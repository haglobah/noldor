{
  writeShellApplication,
  asdbctl,
  coreutils,
  ddcutil,
  gawk,
  libnotify,
  util-linux,
}:
writeShellApplication {
  name = "monitor-brightness";
  runtimeInputs = [
    asdbctl
    coreutils
    ddcutil
    gawk
    libnotify
    util-linux
  ];
  text = builtins.readFile ./monitor-brightness.sh;
}
