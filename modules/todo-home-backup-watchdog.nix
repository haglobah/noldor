{
  config,
  pkgs,
  lib,
  ...
}:
let
  state = "/var/lib/todo-home-backup-watchdog";
  receiver = pkgs.writeShellScript "todo-home-backup-status" ''
    set -euo pipefail
    read -r status
    case "$status" in
      success) ${pkgs.coreutils}/bin/touch ${state}/success; ${pkgs.coreutils}/bin/rm -f ${state}/failed ;;
      failure) ${pkgs.coreutils}/bin/touch ${state}/failed ;;
      *) exit 1 ;;
    esac
    ${pkgs.systemd}/bin/systemctl start todo-home-backup-watchdog.service
  '';
in
{
  imports = [ ./todo-home-backup-key.nix ];
  systemd.tmpfiles.rules = [ "d ${state} 0700 root root -" ];
  users.users.root.openssh.authorizedKeys.keys = [
    ''restrict,command="${receiver}" ${
      config.clan.core.vars.generators.todo-home-backup-transport.files."key.pub".value
    }''
  ];
  systemd.services.todo-home-backup-watchdog = {
    description = "Page if Gondor's daily restore failed or stopped reporting";
    path = [
      pkgs.coreutils
      pkgs.curl
    ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.clan.core.vars.generators.gatus.files.env_file.path;
      TimeoutStartSec = "2min";
    };
    script = ''
      set -euo pipefail
      now=$(date +%s)
      success=$(stat -c %Y ${state}/success 2>/dev/null || echo 0)
      alerted=$(stat -c %Y ${state}/alerted 2>/dev/null || echo 0)
      if [ -f ${state}/failed ] || [ "$((now-success))" -gt 100800 ]; then
        if [ "$((now-alerted))" -gt 21600 ]; then
          curl --fail --silent --show-error --retry 3 --max-time 20 \
            -H 'Title: Todo backup recovery test failed or overdue' -H 'Priority: 5' \
            --data 'Gondor has no successful fresh-backup restore in 28 hours, or its latest run failed. Check todo-home-backup-test.service on Gondor and borgbackup-job-storagebox.service on Orthanc.' \
            "https://ntfy.sh/$NTFY_TOPIC" >/dev/null
          touch ${state}/alerted
        fi
      elif [ -e ${state}/alerted ]; then
        curl --fail --silent --show-error --retry 3 --max-time 20 \
          -H 'Title: Todo backup recovery test recovered' \
          --data 'Gondor successfully restored and checked a fresh offsite backup.' \
          "https://ntfy.sh/$NTFY_TOPIC" >/dev/null
        rm ${state}/alerted
      fi
    '';
  };
  systemd.timers.todo-home-backup-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}
