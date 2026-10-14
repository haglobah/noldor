# Role `client`: substitute from the private R2 cache, after
# cache.nixos.org, and trust the two signing keys: aule's (it builds for
# the scheduler) and gondor's (it pushes what it builds itself). Either key
# can be revoked on its own.
{
  config,
  lib,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  accountId = generators.nix-cache-account.files.account-id;
  keys = [
    generators.nix-builds-builder-key.files.public-key
    generators.nix-cache-signing-key.files.public-key
  ];

  # Public vars are read at eval time. Until they are generated, leave the
  # cache out with a warning instead of breaking the whole machine's eval.
  ready = accountId.exists && lib.all (k: k.exists) keys;
in
{
  imports = [ ./vars.nix ];

  options.nixBuilds.cache = lib.mkOption {
    type = lib.types.raw;
    internal = true;
    description = "The cache's endpoint, for the pusher and scheduler roles.";
  };

  config = {
    nixBuilds.cache = rec {
      inherit ready;
      # Nix signs S3 requests itself. R2 wants the region `auto`; a full
      # endpoint URL makes Nix use path-style addressing.
      endpoint = "https://${accountId.value}.r2.cloudflarestorage.com";
      store = profile: "s3://nix-cache?endpoint=${endpoint}&region=auto&profile=${profile}";
    };

    clan.core.vars.generators.nix-cache-read.files.credentials.deploy = true;

    warnings = lib.optional (!ready) ''
      nix-builds: the R2 substituter is not configured yet. Run the
      `clan vars generate` steps in clanServices/nix-builds/README.md.
    '';

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
  };
}
