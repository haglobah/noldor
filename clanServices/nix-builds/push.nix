# aule's push side (role `builder`): a post-build hook queues every output;
# nix-cache-push.service signs them with aule's key and uploads them with
# their closures.
# No other machine pushes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  cache = config.nixBuilds.cache;
  secretKey = generators.nix-builds-builder-key.files.secret-key.path;
  spool = "/var/lib/nix-cache-push";

  tools = pkgs.callPackage ./push-tools.nix {
    nix = config.nix.package;
    # zstd packs and unpacks much faster than the xz default. Multipart
    # lifts the 5 GiB single-upload limit. The secret-key parameter signs
    # each narinfo on upload without touching signatures in the local store.
    store = "${cache.store "nix-cache-write"}&secret-key=${secretKey}&compression=zstd&parallel-compression=true&multipart-upload=true";
    credentials = generators.nix-cache-write.files.credentials.path;
    inherit spool;
  };

  # Runs inside nix-daemon after every local or remote (build-hook) build.
  # It blocks the build loop, and if it fails no further builds run. So it
  # only queues the outputs and never fails; nix-cache-push.service uploads.
  postBuildHook = pkgs.writeShellScript "nix-cache-queue" ''
    set -f
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    if tmp=$(mktemp ${spool}/incoming/XXXXXXXX) \
      && printf '%s\n' $OUT_PATHS > "$tmp" \
      && mv "$tmp" "${spool}/queue/$(date +%s%N)-''${tmp##*/}"; then
      :
    else
      echo "nix-cache: could not queue $OUT_PATHS for upload to R2" >&2
    fi
    exit 0
  '';
in
{
  # The store URL comes from the client role.
  imports = [ ./client.nix ];

  config = lib.mkMerge [
    {
      # Per machine: only aule holds the secret half.
      clan.core.vars.generators.nix-builds-builder-key = config.nixBuilds.vars.signingKey "noldor-aule-1";
      # Shared like the read token, but only aule declares it.
      clan.core.vars.generators.nix-cache-write =
        config.nixBuilds.vars.awsCredentials "nix-cache-write" "read-write";
    }

    # The store URL needs the account id; ./client.nix warns until it exists.
    (lib.mkIf cache.ready {
      environment.systemPackages = [ tools.nix-cache ];

      nix.settings.post-build-hook = postBuildHook;
    })
    # A literal key: the module system needs it before pkgs exists.
    (lib.mkIf cache.ready { inherit (tools.units) systemd; })
  ];
}
