case "${1:-}" in
  up) delta=+ ;;
  down) delta=- ;;
  *) echo 'Usage: monitor-brightness up|down (10-point steps)' >&2; exit 2 ;;
esac

export LC_ALL=C
# Serialize key repeats so relative updates cannot race each other.
exec 9>"${XDG_RUNTIME_DIR:?No desktop runtime directory}/monitor-brightness.lock"
flock 9

# asdbctl detects supported Apple Studio Displays over USB itself.
if apple_error=$(asdbctl "$1" --step 10 2>&1); then
  exit 0
fi

# Re-detect on each invocation: docking can change the working I2C bus.
# Only use valid Dell displays; laptop panels and failed DDC probes are skipped.
detection=$(ddcutil detect --brief 2>&1) || true
mapfile -t buses < <(awk '
  /^Display [0-9]+/ { valid=1; bus=""; next }
  /^Invalid display/ { valid=0; bus=""; next }
  /I2C bus:/ { bus=$NF; sub("/dev/i2c-", "", bus) }
  /Monitor:[[:space:]]+DEL:/ && valid && bus ~ /^[0-9]+$/ { print bus }
' <<< "$detection")

changed=0
failed=0
for bus in "${buses[@]}"; do
  if ddcutil --bus "$bus" setvcp 10 "$delta" 10; then
    changed=1
  else
    failed=1
  fi
done
if (( changed && !failed )); then
  exit 0
fi

message='Could not adjust monitor brightness. Check DDC/CI and device permissions. If this monitor is unsupported, update home/pkgs/monitor-brightness/monitor-brightness.sh and package its utility in default.nix.'
printf '%s\nApple: %s\nDDC detection:\n%s\n' "$message" "$apple_error" "$detection" >&2
notify-send --urgency=critical 'Monitor brightness' "$message" || true
exit 1
