# Private Cloudflare R2 binary cache (bucket `nix-cache`), read by every
# machine's nix-daemon next to cache.nixos.org. Pushing lives in
# ./nix-cache-push.nix; setup and the one-time vars steps are in
# docs/nix-cache.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  accountId = generators.nix-cache-account.files.account-id;
  publicKey = generators.nix-cache-signing-key.files.public-key;

  # Public vars are read at eval time. Until they are generated, leave the
  # cache out with a warning instead of breaking the whole machine's eval.
  ready = accountId.exists && publicKey.exists;

  # Nix signs S3 requests itself (aws-crt + curl SigV4). R2 wants the
  # region `auto`; a full endpoint URL makes Nix use path-style addressing.
  # Priority 50 puts it after cache.nixos.org (40), so paths that are
  # upstream anyway do not cost R2 requests.
  endpoint = "https://${accountId.value}.r2.cloudflarestorage.com";
  substituter = "s3://nix-cache?endpoint=${endpoint}&region=auto&profile=nix-cache-read&priority=50";

  # One credentials file per token, picked by the `profile=` in the store URL.
  awsCredentials =
    profile: label:
    let
      key = name: ''$(tr -d '[:space:]' < "$prompts/${name}")'';
    in
    {
      share = true;
      files.credentials = { };
      prompts.access-key-id = {
        type = "line";
        description = "R2 ${label} token: Access Key ID";
      };
      prompts.secret-access-key = {
        type = "hidden";
        description = "R2 ${label} token: Secret Access Key";
      };
      script = ''
        {
          echo "[${profile}]"
          echo "aws_access_key_id = ${key "access-key-id"}"
          echo "aws_secret_access_key = ${key "secret-access-key"}"
        } > "$out/credentials"
      '';
    };
in
{
  # Shared with ./nix-cache-push.nix, which adds the read-write token.
  _module.args.nixCache = {
    inherit awsCredentials endpoint ready;
  };

  clan.core.vars.generators = {
    nix-cache-account = {
      share = true;
      # Not secret: it ends up in nix.conf on every machine.
      files.account-id.secret = false;
      prompts.account-id = {
        type = "line";
        description = "Cloudflare account ID (R2 overview page, Account Details)";
      };
      script = ''tr -d '[:space:]' < "$prompts/account-id" > "$out/account-id"'';
    };

    nix-cache-read = awsCredentials "nix-cache-read" "read-only";

    nix-cache-signing-key = {
      share = true;
      files.public-key.secret = false;
      # Only machines that push need to sign; ./nix-cache-push.nix opts in.
      files.secret-key.deploy = lib.mkDefault false;
      runtimeInputs = [ pkgs.nix ];
      script = ''
        nix --extra-experimental-features nix-command \
          key generate-secret --key-name noldor-nix-cache-1 > "$out/secret-key"
        nix --extra-experimental-features nix-command \
          key convert-secret-to-public < "$out/secret-key" > "$out/public-key"
      '';
    };
  };

  warnings = lib.optional (!ready) ''
    nix-cache: the R2 substituter is not configured yet. Run the
    `clan vars generate` steps in docs/nix-cache.md.
  '';

  nix.settings = lib.mkIf ready {
    extra-substituters = [ substituter ];
    extra-trusted-public-keys = [ publicKey.value ];
    # Without fallback an unreachable R2 fails every build of a path that
    # no other cache has; with it Nix builds locally and skips R2 for 60s.
    # Signatures stay required either way.
    fallback = true;
    # Default is 15s per substituter connection; R2 is either quick or down.
    connect-timeout = 5;
  };

  # Nix reads S3 credentials through the AWS default chain, not nix.conf.
  # A file with a named profile instead of AWS_ACCESS_KEY_ID: env vars
  # would win over the profile in every S3 URL, including pushes.
  systemd.services.nix-daemon.environment = lib.mkIf ready {
    AWS_SHARED_CREDENTIALS_FILE = generators.nix-cache-read.files.credentials.path;
  };
}
