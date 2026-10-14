# Clan vars shared between the nix-builds roles. Every generator is shared:
# one value for the whole clan, generated once. A machine declares the
# generators it reads; `deploy` decides which secrets it receives.
{ lib, pkgs, ... }:
let
  # One AWS-style credentials file per R2 token, picked by the `profile=`
  # in the store URL.
  awsCredentials =
    profile: label:
    let
      key = name: ''$(tr -d '[:space:]' < "$prompts/${name}")'';
    in
    {
      share = true;
      files.credentials.deploy = lib.mkDefault false;
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

  # A cache signing key: the public half is trusted everywhere, the secret
  # half only goes to the one machine that signs with it.
  signingKey = keyName: {
    share = true;
    files.public-key.secret = false;
    files.secret-key.deploy = lib.mkDefault false;
    runtimeInputs = [ pkgs.nix ];
    script = ''
      nix --extra-experimental-features nix-command \
        key generate-secret --key-name ${keyName} > "$out/secret-key"
      nix --extra-experimental-features nix-command \
        key convert-secret-to-public < "$out/secret-key" > "$out/public-key"
    '';
  };
in
{
  options.nixBuilds.vars = lib.mkOption {
    type = lib.types.raw;
    internal = true;
    description = "Generator builders, shared with the role modules.";
  };

  config.nixBuilds.vars = { inherit awsCredentials signingKey; };

  config.clan.core.vars.generators = {
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

    # gondor's key (role `pusher`). The name predates nix-builds.
    nix-cache-signing-key = signingKey "noldor-nix-cache-1";
    # aule's key (role `builder`).
    nix-builds-builder-key = signingKey "noldor-aule-1";
  };
}
