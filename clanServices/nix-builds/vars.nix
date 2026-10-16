# Clan vars of the nix-builds roles. clan requires a shared generator to be
# declared alike on every machine (deploy flag included), and encrypts its
# secrets for all of them. So only what every machine needs is shared; a
# secret one machine needs lives on that machine, and the others read its
# public half from the repo (`nixBuilds.publicVar`).
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

  # A cache signing key, per machine: the public half is trusted everywhere.
  signingKey = keyName: {
    files.public-key.secret = false;
    files.secret-key = { };
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
  options.nixBuilds = {
    vars = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      description = "Generator builders, shared with the role modules.";
    };
    builderName = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "The machine with role `builder`; set by ./default.nix.";
    };
    schedulerName = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "The machine with role `scheduler`; set by ./default.nix.";
    };
    publicVar = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      description = "machine: generator: file: { exists; value; } of a public var in the repo.";
    };
  };

  config.nixBuilds.vars = { inherit awsCredentials signingKey; };

  config.nixBuilds.publicVar =
    machine: generator: file:
    let
      path = ../../vars/per-machine/${machine}/${generator}/${file}/value;
      exists = builtins.pathExists path;
    in
    {
      inherit exists;
      value =
        if exists then
          lib.fileContents path
        else
          throw "nix-builds: ${machine}'s ${generator}/${file} is not generated";
    };

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
  };
}
