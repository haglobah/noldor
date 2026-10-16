# VM test for aule's upload (clanServices/nix-builds/push-tools.nix):
# - a queued output whose dependency is not in the cache yet must still
#   upload, signed. A binary cache only accepts a path whose references it
#   already holds; on aule those come from cache.nixos.org or were copied
#   in as sources, and nothing queues them.
# - outputs queued faster than systemd's default start limit (5 in 10 s)
#   must not stop the path unit.
{ pkgs }:
let
  spool = "/var/lib/nix-cache-push";
  cacheDir = "/var/cache/test-cache";
  keys = pkgs.runCommand "nix-builds-push-test-keys" { nativeBuildInputs = [ pkgs.nix ]; } ''
    mkdir $out
    nix --extra-experimental-features nix-command key generate-secret --key-name test-1 > $out/secret
    nix --extra-experimental-features nix-command key convert-secret-to-public < $out/secret > $out/public
  '';
  tools = pkgs.callPackage ../clanServices/nix-builds/push-tools.nix {
    store = "file://${cacheDir}?secret-key=${keys}/secret&compression=zstd";
    credentials = null;
    inherit spool;
  };
  # Its output refers to busybox, which only the local store has.
  drvFile = pkgs.writeText "with-dep.nix" ''
    derivation {
      name = "with-dep";
      system = "${pkgs.stdenv.hostPlatform.system}";
      builder = "''${builtins.storePath "${pkgs.busybox}"}/bin/sh";
      args = [ "-c" "echo ${pkgs.busybox} > $out" ];
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "nix-builds-push";

  nodes.machine = {
    imports = [ tools.units ];
    virtualisation.additionalPaths = [ pkgs.busybox ];
    nix.settings.experimental-features = [ "nix-command" ];
    environment.systemPackages = [ tools.nix-cache-drain ];
  };

  testScript = ''
    machine.wait_for_unit("nix-cache-push.path")
    store = "file://${cacheDir}"
    out = machine.succeed("nix-build --no-out-link ${drvFile}").strip()

    with subtest("an output uploads with its closure, signed"):
        machine.succeed(f"echo {out} > ${spool}/queue/1-test")
        machine.wait_until_succeeds("test -z \"$(ls -A ${spool}/queue)\"", timeout=60)
        machine.succeed("systemctl is-active nix-cache-push.path")
        sigs = machine.succeed(f"nix path-info --store {store} --sigs {out}")
        assert "test-1:" in sigs, sigs
        machine.succeed(f"nix path-info --store {store} ${pkgs.busybox}")

    with subtest("a burst of builds keeps the path unit alive"):
        machine.succeed(
            f"for i in $(seq 10); do echo {out} > ${spool}/queue/burst-$i; sleep 0.5; done"
        )
        machine.wait_until_succeeds("test -z \"$(ls -A ${spool}/queue)\"", timeout=60)
        machine.succeed("systemctl is-active nix-cache-push.path")
  '';
}
