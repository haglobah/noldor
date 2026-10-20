{
  writeShellApplication,
  asdbctl,
  coreutils,
  ddcutil,
  libnotify,
  util-linux,
}:
writeShellApplication {
  name = "monitor-brightness";
  runtimeInputs = [
    asdbctl
    coreutils
    ddcutil
    libnotify
    util-linux
  ];
  text = builtins.readFile ./monitor-brightness.sh;
}
