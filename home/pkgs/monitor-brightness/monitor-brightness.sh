case "${1:-}" in
  up) delta=+ ;;
  down) delta=- ;;
  *) echo 'Usage: monitor-brightness up|down (10-point steps)' >&2; exit 2 ;;
esac

export LC_ALL=C
# Serialize key repeats so relative updates cannot race each other.
exec 9>"${XDG_RUNTIME_DIR:?No desktop runtime directory}/monitor-brightness.lock"
flock 9

sysfs_root=${MONITOR_BRIGHTNESS_SYSFS_ROOT:-/sys}

changed=0
failed=0

# asdbctl detects supported Apple Studio Displays over USB itself.
if apple_error=$(asdbctl "$1" --step 10 2>&1); then
  changed=1
fi

# Address DDC only to connected external monitors, never `ddcutil detect`:
# probing every bus sends DDC/CI to the Studio Display, which has none, and
# its Thunderbolt DP receiver answers by dropping the video link.
buses=()
for connector in "$sysfs_root"/class/drm/card*-*; do
  [[ "$(cat "$connector/status" 2>/dev/null)" == connected ]] || continue
  [[ "$connector" == *-eDP-* ]] && continue
  # EDID bytes 8-9 pack the PNP vendor ID; 06 10 is APP (Apple).
  vendor=$(od -An -tx1 -j8 -N2 "$connector/edid" 2>/dev/null | tr -d ' ')
  [[ "$vendor" == 0610 ]] && continue
  # DP connectors own their AUX I2C adapter; HDMI points at it via ddc.
  adapter=$(find "$connector" -maxdepth 1 -name 'i2c-*' -printf '%f\n' -quit)
  if [[ -z "$adapter" && -L "$connector/ddc" ]]; then
    adapter=$(basename "$(readlink "$connector/ddc")")
  fi
  [[ -n "$adapter" ]] && buses+=("${adapter#i2c-}")
done

ddc_error=''
for bus in "${buses[@]}"; do
  if output=$(ddcutil --bus "$bus" setvcp 10 "$delta" 10 2>&1); then
    changed=1
  else
    failed=1
    ddc_error+="bus $bus: $output"$'\n'
  fi
done
if (( changed && !failed )); then
  exit 0
fi

message='Could not adjust brightness on one or more monitors. Check DDC/CI and device permissions. Monitors must support DDC brightness control or Apple Studio Display USB control.'
printf '%s\nApple: %s\nDDC:\n%s' "$message" "$apple_error" "$ddc_error" >&2
notify-send --urgency=critical 'Monitor brightness' "$message" || true
exit 1
