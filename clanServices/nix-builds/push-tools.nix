# aule's upload tools, apart from clan vars so tests/nix-builds-push.nix
# can run them against a local cache. `store` is the full push URL,
# signing key included; `credentials` an AWS credentials file or null.
{
  lib,
  writeShellApplication,
  coreutils,
  nix,
  store,
  credentials,
  spool,
}:
rec {
  # `nix-cache push PATH...` uploads with closures, `nix-cache info PATH...` shows what
  # the cache holds. Root only: the write token and signing key are
  # root-owned.
  nix-cache = writeShellApplication {
    name = "nix-cache";
    runtimeInputs = [ nix ];
    text = ''
      if [ "$(id -u)" != 0 ]; then
        echo "nix-cache: run as root (sudo); the R2 write token is root-only" >&2
        exit 1
      fi
      ${lib.optionalString (credentials != null) "export AWS_SHARED_CREDENTIALS_FILE=${credentials}"}
      nix=(nix --extra-experimental-features nix-command)

      case "''${1:-}" in
        push)
          shift
          "''${nix[@]}" copy --to "${store}" "$@"
          ;;
        info)
          shift
          "''${nix[@]}" path-info --store "${store}" --sigs "$@"
          ;;
        *)
          echo "usage: nix-cache push [--no-recursive] PATH... | nix-cache info PATH..." >&2
          exit 1
          ;;
      esac
    '';
  };

  # Drains the queue that the post-build hook fills. A failed upload stays
  # queued and makes the run exit 1.
  nix-cache-drain = writeShellApplication {
    name = "nix-cache-drain";
    runtimeInputs = [
      nix-cache
      coreutils
    ];
    text = ''
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
          # With their closures: a binary cache only takes a path whose
          # references it holds, and dependencies substituted from
          # cache.nixos.org or copied in as sources are never queued.
          # nix copy skips what the cache already has.
          if [ ''${#paths[@]} -eq 0 ] || nix-cache push "''${paths[@]}"; then
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

  # The spool and the units that drain it, as NixOS config.
  units = {
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
      # Every finished build triggers it, often several times a second.
      # Past the default limit (5 starts in 10 s) systemd fails the path
      # unit for good. PathChanged cannot loop, so no limit is needed.
      startLimitIntervalSec = 0;
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = lib.getExe nix-cache-drain;
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
  };
}
