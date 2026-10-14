# aule: on-demand Hetzner Cloud build machine for gondor. gondor creates it
# from a snapshot (./nix-builder-client.nix), sends builds over ssh-ng, and
# aule deletes itself when idle. It holds no cache credentials: gondor's
# post-build hook pushes what aule builds once the outputs are copied back.
# See docs/nix-builder.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  builderKey = generators.nix-builder-ssh.files."id_ed25519.pub";
  state = "/run/nix-builder-reaper";

  reap-decide = pkgs.callPackage ./nix-builder/reap-decide.nix { };

  reaper = pkgs.writeShellApplication {
    name = "nix-builder-reaper";
    runtimeInputs = [
      reap-decide
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.procps
      config.systemd.package
    ];
    text = ''
      api=https://api.hetzner.cloud/v1
      token=$(< ${generators.hcloud-token.files.token.path})
      mkdir -p ${state}

      # Busy: a client is connected to nix-daemon (each connection is a
      # child of the main daemon; builds, copies and substitutions all
      # run under one), gondor's ssh-ng session is open (nix-ssh), or
      # someone is logged in (clan machines update, a debugging shell).
      # Live process state, not a marker file: a marker that builds touch
      # goes stale when a build crashes or a client hangs mid-transfer.
      busy() {
        local main
        main=$(systemctl show --property MainPID --value nix-daemon.service)
        { [ "$main" != 0 ] && pgrep -P "$main" > /dev/null; } \
          || pgrep -u nix-ssh > /dev/null \
          || [ -n "$(loginctl list-sessions --no-legend)" ]
      }

      # last-busy lives in /run, so every boot (and every server made
      # from the snapshot) starts with a fresh 10-minute grace period.
      [ -e ${state}/last-busy ] || touch ${state}/last-busy
      now=$(date +%s)
      if busy; then
        touch ${state}/last-busy
        is_busy=1
      else
        is_busy=0
      fi
      last_busy=$(stat -c %Y ${state}/last-busy)

      if [ ! -s ${state}/id ]; then
        curl -fsS --max-time 5 http://169.254.169.254/hetzner/v1/metadata/instance-id > ${state}/id.tmp
        mv ${state}/id.tmp ${state}/id
      fi
      id=$(< ${state}/id)

      # Hetzner bills from the server's creation, not from this boot.
      if [ ! -s ${state}/created ]; then
        created=$(curl -fsS --max-time 10 -H "Authorization: Bearer $token" "$api/servers/$id" \
          | jq -r .server.created)
        date -d "$created" +%s > ${state}/created
      fi
      created=$(< ${state}/created)

      decision=$(reap-decide "$now" "$created" "$last_busy" "$is_busy")
      age=$(((now - created) / 60))
      echo "$decision (age $age min, idle $(((now - last_busy) / 60)) min)"

      case $decision in
        "delete idle")
          # A build may have started since the check above.
          if busy; then
            echo "busy again, keeping"
            exit 0
          fi
          echo "<5>deleting server $id: idle near the end of a billed hour"
          ;;
        "delete cap")
          echo "<3>deleting server $id: over the ''${REAP_CAP_MIN:-360} min cap after $age min, even if a build is running"
          ;;
        *) exit 0 ;;
      esac
      curl -fsS --max-time 30 -X DELETE -H "Authorization: Bearer $token" "$api/servers/$id" > /dev/null
    '';
  };
in
{
  imports = [ ./nix-builder-vars.nix ];

  # gondor's nix-daemon logs in as nix-ssh, which may only run
  # `nix-daemon --stdio`. It must be trusted to build derivations that are
  # not signed by a key aule trusts; that is equivalent to root on the store.
  nix.sshServe = {
    enable = true;
    protocol = "ssh-ng";
    trusted = true;
    keys = lib.optional builderKey.exists builderKey.value;
  };
  warnings = lib.optional (!builderKey.exists) ''
    nix-builder: no gondor key for nix-ssh yet. Run
    `clan vars generate gondor -g nix-builder-ssh` (docs/nix-builder.md).
  '';

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # CX53: 16 vCPU, 32 GB. 4 jobs x 4 cores fills the CPUs and leaves
    # ~8 GB per job. On a CCX33 (8 vCPU) it oversubscribes 2x, which is fine.
    max-jobs = 4;
    cores = 4;
    # Hard-linking every new path costs build time; the store lives an
    # hour or two and is never snapshotted with build results in it.
    auto-optimise-store = false;
    # Collect garbage during builds when free space drops below 10 GiB.
    min-free = 10 * 1024 * 1024 * 1024;
    max-free = 40 * 1024 * 1024 * 1024;
  };

  # Absorbs memory spikes of big link steps instead of OOM-killing them.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  systemd.services.nix-builder-reaper = {
    description = "Delete this Hetzner server when idle near the end of a billed hour";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe reaper;
    };
  };
  systemd.timers.nix-builder-reaper = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "5s";
    };
  };
}
