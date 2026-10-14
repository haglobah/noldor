# VM test for the trust boundary of clanServices/nix-builds: the scheduler
# logs in to the builder as an *untrusted* nix-ssh user. It must be able to
# copy derivations and have them built, but must not be able to import an
# unsigned output path (which aule's push hook would then sign).
{ pkgs }:
let
  keys = pkgs.runCommand "nix-builds-test-keys" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir $out
    ssh-keygen -t ed25519 -N "" -f $out/id_ed25519
  '';
  # The build's only tool; valid in both stores, so copying the derivation
  # never has to send it (an input-addressed path would need a signature).
  busybox = "${pkgs.busybox}";
  drvFile =
    name:
    pkgs.writeText "${name}.nix" ''
      derivation {
        name = "${name}";
        system = "${pkgs.stdenv.hostPlatform.system}";
        builder = "''${builtins.storePath "${busybox}"}/bin/sh";
        args = [ "-c" "echo built-on-builder > $out" ];
      }
    '';
in
pkgs.testers.runNixOSTest {
  name = "nix-builds-untrusted";

  nodes.builder = {
    virtualisation.additionalPaths = [ pkgs.busybox ];
    nix.settings.experimental-features = [ "nix-command" ];
    nix.sshServe = {
      enable = true;
      protocol = "ssh-ng";
      trusted = false;
      keys = [ (builtins.readFile "${keys}/id_ed25519.pub") ];
    };
    services.openssh.enable = true;
  };

  nodes.scheduler = {
    virtualisation.additionalPaths = [ pkgs.busybox ];
    nix.settings.experimental-features = [ "nix-command" ];
    # Only signed paths count on the builder; this one signs nothing.
    nix.settings.require-sigs = true;
  };

  testScript = ''
    import json

    start_all()
    builder.wait_for_unit("sshd.service")
    scheduler.wait_for_unit("multi-user.target")

    scheduler.succeed(
      "install -Dm600 ${keys}/id_ed25519 /root/.ssh/id_ed25519",
      "ssh-keyscan builder > /root/.ssh/known_hosts",
    )
    store = "ssh-ng://nix-ssh@builder"

    with subtest("the untrusted user is untrusted"):
        info = json.loads(scheduler.succeed(f"nix store info --store {store} --json"))
        assert info["trusted"] is False, info

    with subtest("derivations copy and build as the untrusted user"):
        drv = scheduler.succeed(
            "nix-instantiate ${drvFile "remote-build"}"
        ).strip()
        scheduler.succeed(f"nix copy --derivation --to {store} {drv}")
        out = scheduler.succeed(f"nix build --store {store} --no-link --print-out-paths '{drv}^*'").strip()
        builder.succeed(f"grep -q built-on-builder {out}")
        # Outputs stay on the builder; the scheduler needs no build space.
        scheduler.fail(f"test -e {out}")

    with subtest("an unsigned output cannot be imported"):
        local = scheduler.succeed(
            "nix-build --no-out-link ${drvFile "local-build"}"
        ).strip()
        err = scheduler.fail(f"nix copy --to {store} {local} 2>&1")
        print(err)
        builder.fail(f"nix path-info {local}")
  '';
}
