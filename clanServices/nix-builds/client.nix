# Role `client`: substitute from the private R2 cache, after
# cache.nixos.org, and trust aule's signing key. Only aule pushes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  accountId = generators.nix-cache-account.files.account-id;
  # aule's public key, read from the repo: the generator lives on aule only.
  keys = [
    (config.nixBuilds.publicVar config.nixBuilds.builderName "nix-builds-builder-key" "public-key")
  ];

  # Public vars are read at eval time. Until they are generated, leave the
  # cache out with a warning instead of breaking the whole machine's eval.
  ready = accountId.exists && lib.all (k: k.exists) keys;

  # `nix-cache-info PATH...`: what R2 holds for these paths, with
  # signatures. Root only: the read token is root-owned.
  nix-cache-info = pkgs.writeShellApplication {
    name = "nix-cache-info";
    runtimeInputs = [ config.nix.package ];
    text = ''
      if [ "$(id -u)" != 0 ]; then
        echo "nix-cache-info: run as root (sudo); the R2 read token is root-only" >&2
        exit 1
      fi
      export AWS_SHARED_CREDENTIALS_FILE=${generators.nix-cache-read.files.credentials.path}
      nix --extra-experimental-features nix-command path-info --sigs \
        --option narinfo-cache-negative-ttl 0 \
        --store "${config.nixBuilds.cache.store "nix-cache-read"}" "$@"
    '';
  };
in
{
  imports = [ ./vars.nix ];

  options.nixBuilds.cache = lib.mkOption {
    type = lib.types.raw;
    internal = true;
    description = "The cache's endpoint, for the builder and scheduler roles.";
  };

  config = {
    nixBuilds.cache = rec {
      inherit ready;
      # Nix signs S3 requests itself. R2 wants the region `auto`; a full
      # endpoint URL makes Nix use path-style addressing.
      endpoint = "https://${accountId.value}.r2.cloudflarestorage.com";
      store = profile: "s3://nix-cache?endpoint=${endpoint}&region=auto&profile=${profile}";
    };

    warnings = lib.optional (!ready) ''
      nix-builds: the R2 substituter is not configured yet. Run the
      `clan vars generate` steps in clanServices/nix-builds/README.md.
    '';

    environment.systemPackages = lib.mkIf ready [ nix-cache-info ];

    nix.settings = lib.mkIf ready {
      # Priority 50 puts it after cache.nixos.org (40), so paths that are
      # upstream anyway cost no R2 requests.
      extra-substituters = [ "${config.nixBuilds.cache.store "nix-cache-read"}&priority=50" ];
      extra-trusted-public-keys = map (k: k.value) keys;
      # An unreachable R2 must not fail builds of paths no other cache has;
      # Nix builds locally instead. Signatures stay required either way.
      fallback = true;
      connect-timeout = 5;
    };

    # Nix reads S3 credentials through the AWS default chain, not nix.conf.
    # A file with a named profile instead of AWS_ACCESS_KEY_ID: env vars
    # would win over the profile in every S3 URL, including pushes.
    systemd.services.nix-daemon.environment = lib.mkIf ready {
      AWS_SHARED_CREDENTIALS_FILE = generators.nix-cache-read.files.credentials.path;
    };

    # root's nix opens the store itself (store = auto), so it queries R2 in
    # its own process, without the daemon's environment: `clan machines
    # update` got HTTP 400 and built instead. The SDK's default file reaches
    # every root process, ssh sessions without a login shell included.
    systemd.tmpfiles.rules = lib.mkIf ready [
      "d /root/.aws 0700 root root -"
      "L+ /root/.aws/credentials - - - - ${generators.nix-cache-read.files.credentials.path}"
    ];
  };
}
