# aule's push side (role `builder`): a post-build hook queues every output;
# nix-cache-push.service signs them with aule's key and uploads the queue.
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

  # `nix-cache push [--no-recursive] PATH...` uploads, `nix-cache info PATH...`
  # shows what the cache holds. Root only: the write token and signing key
  # are root-owned. The secret-key parameter signs each narinfo on upload
  # without touching signatures in the local store.
  nix-cache = pkgs.writeShellApplication {
    name = "nix-cache";
    runtimeInputs = [ config.nix.package ];
    text = ''
      if [ "$(id -u)" != 0 ]; then
        echo "nix-cache: run as root (sudo); the R2 write token is root-only" >&2
        exit 1
      fi
      export AWS_SHARED_CREDENTIALS_FILE=${generators.nix-cache-write.files.credentials.path}
      store="${cache.store "nix-cache-write"}"
      nix=(nix --extra-experimental-features nix-command)

      case "''${1:-}" in
        push)
          shift
          # zstd packs and unpacks much faster than the xz default.
          # Multipart lifts the 5 GiB single-upload limit.
          "''${nix[@]}" copy \
            --to "$store&secret-key=${secretKey}&compression=zstd&parallel-compression=true&multipart-upload=true" \
            "$@"
          ;;
        info)
          shift
          "''${nix[@]}" path-info --store "$store" --sigs "$@"
          ;;
        *)
          echo "usage: nix-cache push [--no-recursive] PATH... | nix-cache info PATH..." >&2
          exit 1
          ;;
      esac
    '';
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
      environment.systemPackages = [ nix-cache ];

      nix.settings.post-build-hook = postBuildHook;

      systemd.tmpfiles.rules = [
        "d ${spool} 0700 root root -"
        "d ${spool}/incoming 0700 root root -"
        "d ${spool}/queue 0700 root root -"
      ];

      # Drains the queue. A failed upload (offline laptop, R2 down) stays
      # queued, fails the unit so it shows in `systemctl --failed`, and is
      # retried by the timer.
      systemd.services.nix-cache-push = {
        description = "Upload queued Nix build outputs to the R2 cache";
        path = [
          nix-cache
          pkgs.coreutils
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          failed=0
          declare -A tried=()
          # Rescan until nothing new turns up: the hook keeps queueing while we
          # upload, and its trigger only joins this already running job.
          while :; do
            progress=0
            for entry in ${spool}/queue/*; do
              [ -e "$entry" ] || continue
              [ -z "''${tried[$entry]:-}" ] || continue
              tried[$entry]=1
              progress=1
              paths=()
              while read -r p; do
                if [ -e "$p" ]; then
                  paths+=("$p")
                else
                  echo "skipping $p: garbage-collected before upload"
                fi
              done < "$entry"
              # Only the outputs: their dependencies were either substituted,
              # so a cache has them, or built here and queued on their own.
              if [ ''${#paths[@]} -eq 0 ] || nix-cache push --no-recursive "''${paths[@]}"; then
                rm -f "$entry"
              else
                echo "upload failed, keeping $entry queued"
                failed=1
              fi
            done
            [ "$progress" = 1 ] || break
          done
          exit "$failed"
        '';
      };

      systemd.paths.nix-cache-push = {
        wantedBy = [ "paths.target" ];
        # PathChanged, not DirectoryNotEmpty: a failed upload leaves the queue
        # non-empty, which would retrigger the service in a tight loop.
        pathConfig.PathChanged = "${spool}/queue";
      };

      systemd.timers.nix-cache-push = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitInactiveSec = "15min";
        };
      };
    })
  ];
}
