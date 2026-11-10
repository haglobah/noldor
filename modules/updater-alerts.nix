# A failed Todo or Mail updater run on orthanc posts to the same secret
# ntfy.sh topic that Gatus pages on (./monitoring.nix). The updater's
# OnFailure unit says whether it rolled back, and quotes the failed run's
# log. On cirdan only the var is used, by pushout-notes' updater
# (./pushout-notes.nix); the services below are set where they exist.
#
# The topic is copied once from the gatus var instead of prompted again:
#   clan vars get formenos gatus/env_file | clan vars set <machine> updater-alerts/env_file
#
# Fetch failures are gated here, until the updater (ht's nix/updater, ported
# to pushout's notes/nix/updater) gates them itself. On 2026-11-10 a
# thrashing orthanc made every updater's `git fetch` fail on most ticks; each
# failure posted and each good tick after it posted "healthy again", ~150
# messages that used up ntfy.sh's daily quota and dropped Gatus' pages. A
# fetch failure (git exits 128, or curl 6/7/28, before any build) now posts only once it has
# lasted fetchGraceMinutes without a good run in between, only while no alert
# of that updater is open, and only one per host per hostWindowMinutes. So
# flapping posts nothing, and an outage posts one failure and one recovery.
# Build, health, soak and rollback failures post as before.
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  fetchGraceMinutes = 30;
  hostWindowMinutes = 60;
  hostDir = "/var/lib/updater-alerts";

  # The updaters with notify on, by systemd name (their units are
  # <name>-updater and <name>-updater-notify, their state /var/lib/<name>-updater).
  candidates =
    lib.optionals (options.services ? todo-home) (
      map (i: {
        name = "todo-home-${i}";
        enable = (config.services.todo-home.${i} or { enable = false; }).enable;
        au = config.services.todo-home.${i}.autoUpdate;
      }) [ "prod" "dev" ]
    )
    ++ lib.optionals (options.services ? humane-mail) (
      map (i: {
        name = "humane-mail-${i}";
        enable = (config.services.humane-mail.instances.${i} or { enable = false; }).enable;
        au = config.services.humane-mail.instances.${i}.autoUpdate;
      }) [ "prod" "dev" ]
    )
    ++ lib.optional (options.services ? pushout-notes) {
      name = "pushout-notes";
      inherit (config.services.pushout-notes) enable;
      au = config.services.pushout-notes.autoUpdate;
    };

  # ExecStopPost of the updater: systemd sets SERVICE_RESULT and EXIT_STATUS
  # there, and the unit only turns failed (and starts OnFailure=) after it.
  # It leaves "post" or "skip" in $STATE/notify-gate for the notify unit.
  gate =
    name:
    pkgs.writeShellScript "${name}-updater-alert-gate" ''
      set -u
      export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.findutils ]}
      STATE=/var/lib/${name}-updater
      SINCE=$STATE/fetch-failing-since
      HOST=${hostDir}/fetch-alerted
      mkdir -p "$STATE" ${hostDir}
      fresh() { [ -n "$(find "$1" -mmin -"$2" 2>/dev/null)" ]; }
      decide() { echo "$1" > "$STATE/notify-gate"; echo "Alert gate: $1 ($2)"; }

      # 128: git fetch; 6, 7, 28: curl could not resolve, connect, or timed
      # out (the release and cache checks). All before any build.
      case "''${SERVICE_RESULT:-}:''${EXIT_STATUS:-}" in
        exit-code:128 | exit-code:6 | exit-code:7 | exit-code:28) transient=1 ;;
        *) transient= ;;
      esac
      if [ -z "$transient" ]; then
        # Not a fetch failure: the fetch worked, or the run failed later.
        rm -f "$SINCE"
        decide post "not a fetch failure"
        exit 0
      fi
      [ -e "$SINCE" ] || touch "$SINCE"
      if [ -e "$STATE/alerted" ]; then
        decide skip "an alert of ${name} is still open"
      elif fresh "$SINCE" ${toString fetchGraceMinutes}; then
        decide skip "fetch failing for under ${toString fetchGraceMinutes} min"
      elif fresh "$HOST" ${toString hostWindowMinutes} && [ "$(cat "$HOST")" != ${name} ]; then
        decide skip "$(cat "$HOST") posted a fetch failure on this host within ${toString hostWindowMinutes} min"
      else
        echo ${name} > "$HOST"
        decide post "fetch failing for ${toString fetchGraceMinutes} min or more"
      fi
      exit 0
    '';

  # ExecCondition of the notify unit: exit 1 skips the post without failing
  # the unit. No gate file (never written yet) posts.
  condition =
    name:
    pkgs.writeShellScript "${name}-updater-notify-condition" ''
      GATE=/var/lib/${name}-updater/notify-gate
      if [ "$(${pkgs.coreutils}/bin/cat "$GATE" 2>/dev/null)" = skip ]; then
        echo "Not posting: the alert gate skipped this failure"
        exit 1
      fi
    '';

  gated =
    u:
    lib.mkIf (u.enable && u.au.enable && u.au.notify.enable) {
      "${u.name}-updater".serviceConfig.ExecStopPost = [ "-${gate u.name}" ];
      "${u.name}-updater-notify".serviceConfig.ExecCondition = [ "${condition u.name}" ];
    };
  notify = priority: {
    enable = true;
    environmentFile = config.clan.core.vars.generators.updater-alerts.files.env_file.path;
    inherit priority;
  };
in
{
  clan.core.vars.generators.updater-alerts = {
    files."env_file" = { };
    prompts."ntfy-topic" = {
      type = "line";
      description = "The (secret) ntfy.sh topic Gatus pages on; see `clan vars get formenos gatus/env_file`";
    };
    script = ''
      echo "NTFY_TOPIC=$(cat $prompts/ntfy-topic)" > "$out/env_file"
    '';
  };

  # Same priorities as Gatus: prod pages (5), dev is a plain note (3).
  services =
    lib.optionalAttrs (options.services ? todo-home) {
      todo-home.prod.autoUpdate.notify = notify 5;
      todo-home.dev.autoUpdate.notify = notify 3;
    }
    // lib.optionalAttrs (options.services ? humane-mail) {
      humane-mail.instances.prod.autoUpdate.notify = notify 5;
      humane-mail.instances.dev.autoUpdate.notify = notify 3;
    };

  systemd.services = lib.mkMerge (map gated candidates);
}
