case "${1:-}" in
  up) delta=+ ;;
  down) delta=- ;;
  *) echo 'Usage: monitor-brightness up|down (10-point steps)' >&2; exit 2 ;;
esac

export LC_ALL=C
# Serialize key repeats so relative updates cannot race each other.
exec 9>"${XDG_RUNTIME_DIR:?No desktop runtime directory}/monitor-brightness.lock"
flock 9

umask 077
cache_dir="$XDG_RUNTIME_DIR/monitor-brightness"
mkdir -p "$cache_dir"
cache_file="$cache_dir/displays"
sysfs_root=${MONITOR_BRIGHTNESS_SYSFS_ROOT:-/sys}

# Hash kernel-provided connection data, not slow DDC requests. Include adapter
# identities because docking can renumber the working bus independently of EDID.
connection_snapshot() {
  [[ -d "$sysfs_root/class/drm" ]] || return 1
  {
    local connector status adapter
    for connector in "$sysfs_root"/class/drm/card*-*; do
      [[ -f "$connector/status" ]] || continue
      status=$(cat "$connector/status") || return 1
      printf '%s\0%s\0' "$connector" "$status"
      if [[ "$status" == connected ]]; then
        cat "$connector/edid" || return 1
        printf '\0'
        if [[ -L "$connector/ddc" ]]; then
          readlink "$connector/ddc" || return 1
        fi
      fi
    done
    for adapter in "$sysfs_root"/class/i2c-dev/i2c-*; do
      [[ -L "$adapter" ]] || continue
      printf '%s\0' "$adapter"
      readlink "$adapter" || return 1
    done
  } | sha256sum
}

snapshot=$(connection_snapshot)
detection=''
refresh_cache() {
  local after temporary
  rm -f "$cache_file"
  if ! detection=$(ddcutil detect --brief 2>&1); then
    return 1
  fi
  after=$(connection_snapshot) || return 1
  if [[ "$snapshot" != "$after" ]]; then
    detection+=$'\nDisplay connections changed during discovery; press again.'
    return 1
  fi
  temporary=$(mktemp "$cache_dir/displays.XXXXXX") || return 1
  if ! printf '%s\n%s\n' "$snapshot" "$detection" > "$temporary" ||
     ! mv "$temporary" "$cache_file"; then
    rm -f "$temporary"
    return 1
  fi
}

changed=0
failed=0

# asdbctl detects supported Apple Studio Displays over USB itself.
if apple_error=$(asdbctl "$1" --step 10 2>&1); then
  changed=1
fi

# Reuse discovery until the connection snapshot changes.
if [[ -f "$cache_file" ]] && [[ $(head -n 1 "$cache_file") == "$snapshot" ]]; then
  detection=$(tail -n +2 "$cache_file")
elif ! refresh_cache; then
  failed=1
fi

# Use every valid DDC display regardless of brand; skip failed DDC probes.
# A detected display may lack brightness control; report any failed write below.
buses=()
if (( !failed )); then
mapfile -t buses < <(awk '
  /^Display [0-9]+/ { valid=1; bus=""; next }
  /^Invalid display/ { valid=0; bus=""; next }
  /I2C bus:/ { bus=$NF; sub("/dev/i2c-", "", bus) }
  /Monitor:/ && valid && bus ~ /^[0-9]+$/ { print bus }
' <<< "$detection")
fi

write_failed=0
for bus in "${buses[@]}"; do
  if ddcutil --bus "$bus" setvcp 10 "$delta" 10; then
    changed=1
  else
    failed=1
    write_failed=1
  fi
done
if (( write_failed )); then
  # A failed verification can follow a successful write. Refresh for the next
  # key press, but never replay a relative change whose outcome is uncertain.
  printf 'Brightness write failed; refreshing display discovery for the next key press.\n' >&2
  if snapshot=$(connection_snapshot); then
    refresh_cache || rm -f "$cache_file"
  else
    rm -f "$cache_file"
  fi
fi
if (( changed && !failed )); then
  exit 0
fi

message='Could not adjust brightness on one or more monitors. Check DDC/CI and device permissions. Monitors must support DDC brightness control or Apple Studio Display USB control.'
printf '%s\nApple: %s\nDDC detection:\n%s\n' "$message" "$apple_error" "$detection" >&2
notify-send --urgency=critical 'Monitor brightness' "$message" || true
exit 1
