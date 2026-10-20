# Brings the Apple Studio Display's picture back when it gets stuck dark.
#
# The display sometimes withdraws its Thunderbolt DP OUT adapters on its own
# and never offers them again: the USB4 link stays up (camera, speakers, USB
# work), but no DRM connector shows it, and re-probing the connector does
# nothing. Rebinding the thunderbolt driver resets the host router
# (thunderbolt.host_reset defaults to on), which the display takes as a
# replug. This watches for "attached over Thunderbolt but no Apple EDID on any
# connected connector" and does that reset, backing off while it keeps failing.
{ pkgs, ... }:
let
  watchdog = pkgs.writeShellApplication {
    name = "studio-display-watchdog";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      grace=15 # seconds dark before acting; covers resume and normal replugs
      backoff=30

      # Prints the PCI address of the USB4 host the display hangs off, if attached.
      display_host() {
        local dev path
        for dev in /sys/bus/thunderbolt/devices/*; do
          [[ "$(cat "$dev/vendor_name" 2>/dev/null)" == Apple* ]] || continue
          [[ "$(cat "$dev/device_name" 2>/dev/null)" == "Studio Display"* ]] || continue
          path=$(readlink -f "$dev")
          path=''${path%%/domain*}
          basename "$path"
          return 0
        done
        return 1
      }

      # EDID bytes 8-9 pack the PNP vendor ID; 06 10 is APP (Apple).
      has_picture() {
        local connector
        for connector in /sys/class/drm/card*-DP-*; do
          [[ "$(cat "$connector/status" 2>/dev/null)" == connected ]] || continue
          [[ "$(od -An -tx1 -j8 -N2 "$connector/edid" 2>/dev/null | tr -d ' ')" == 0610 ]] && return 0
        done
        return 1
      }

      dark_since=""
      while sleep 5; do
        if ! host=$(display_host) || has_picture; then
          dark_since=""
          backoff=30
          continue
        fi
        now=$(date +%s)
        dark_since=''${dark_since:-$now}
        (( now - dark_since >= grace )) || continue

        echo "Studio Display attached via $host without a picture for $((now - dark_since))s; resetting the host router"
        echo "$host" > /sys/bus/pci/drivers/thunderbolt/unbind || true
        sleep 2
        echo "$host" > /sys/bus/pci/drivers/thunderbolt/bind || true

        sleep "$backoff"
        if has_picture; then
          echo "Studio Display picture restored"
        else
          backoff=$(( backoff * 2 > 600 ? 600 : backoff * 2 ))
          echo "Studio Display still dark; waiting at least ''${backoff}s after the next reset"
        fi
        dark_since=""
      done
    '';
  };
in
{
  systemd.services.studio-display-watchdog = {
    description = "Reset Thunderbolt when the Studio Display is attached but dark";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${watchdog}/bin/studio-display-watchdog";
      Restart = "always";
      RestartSec = 10;
    };
  };
}
