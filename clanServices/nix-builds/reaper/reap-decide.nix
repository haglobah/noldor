# Pure decision for aule's self-deletion; ../builder.nix feeds it the
# clock, the server's creation time and the build activity.
{ writeShellApplication }:
writeShellApplication {
  name = "reap-decide";
  text = builtins.readFile ./reap-decide.sh;
}
