{
  writeShellApplication,
  asdbctl,
  ddcutil,
  gawk,
  libnotify,
  util-linux,
}:
writeShellApplication {
  name = "monitor-brightness";
  runtimeInputs = [
    asdbctl
    ddcutil
    gawk
    libnotify
    util-linux
  ];
  text = builtins.readFile ./monitor-brightness.sh;
}
