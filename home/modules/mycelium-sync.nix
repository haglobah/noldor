{ pkgs, ... }:
# Auto-commit and push the mycelium notes vault every 20 minutes.
#
# The vault is edited from Emacs and Obsidian, so the sync lives at the repo
# level rather than in either editor. A timer batches saves into one commit;
# inotify-based tools (git-sync, gitwatch) would commit on every save and race
# with editors mid-write.
#
# Failures are left visible on purpose: no `|| true` on pull or push. The unit
# shows up in `systemctl --user --failed`, the commit is already safe locally,
# and the next timer run retries. Merge conflicts are never auto-resolved; a
# failed rebase aborts and the unit fails.
let
  sync = pkgs.writeShellApplication {
    name = "mycelium-sync";
    runtimeInputs = with pkgs; [
      git
      openssh
      coreutils
      hostname
    ];
    text = ''
      cd "$HOME/mycelium"

      git add -A
      if ! git diff --cached --quiet; then
        git commit --quiet --message "auto: $(hostname) $(date +'%Y-%m-%d %H:%M')"
      fi

      if ! git pull --rebase --autostash --quiet; then
        git rebase --abort || true
        echo "mycelium-sync: pull --rebase failed, left repository as-is" >&2
        exit 1
      fi

      git push --quiet
    '';
  };
in
{
  systemd.user.services.mycelium-sync = {
    Unit = {
      Description = "Commit and push the mycelium vault";
      ConditionPathIsDirectory = "%h/mycelium/.git";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${sync}/bin/mycelium-sync";
    };
  };

  systemd.user.timers.mycelium-sync = {
    Unit.Description = "Commit and push the mycelium vault every 20 minutes";
    Timer = {
      # Relative timers rather than OnCalendar: a calendar timer with
      # Persistent=true fires a burst right after resume, when the network
      # is least ready.
      OnBootSec = "5min";
      OnUnitActiveSec = "20min";
      RandomizedDelaySec = "2min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
