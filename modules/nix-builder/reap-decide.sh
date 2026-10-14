# reap-decide NOW CREATED LAST_BUSY BUSY
#
# Decides whether aule should delete itself. All times are Unix seconds:
# NOW the clock, CREATED the server's creation time (Hetzner bills every
# started hour from there), LAST_BUSY the last time a build or session was
# seen, BUSY 1 if one is running right now.
#
# Prints one line: "keep busy|recent|early" or "delete idle|cap".
# Thresholds in minutes come from the environment.

idle_min=${REAP_IDLE_MIN:-10}  # no build for this long
hour_min=${REAP_HOUR_MIN:-50}  # and at least this far into the billed hour
cap_min=${REAP_CAP_MIN:-360}   # delete even when busy after this long

if [ $# -ne 4 ]; then
  echo "usage: reap-decide NOW CREATED LAST_BUSY BUSY" >&2
  exit 2
fi
for v in "$@" "$idle_min" "$hour_min" "$cap_min"; do
  case $v in
    '' | *[!0-9]*)
      echo "reap-decide: not a non-negative integer: '$v'" >&2
      exit 2
      ;;
  esac
done

now=$1 created=$2 last_busy=$3 busy=$4
age=$((now - created))

# The cap protects the bill from a hung build or a forgotten session.
if [ "$age" -ge $((cap_min * 60)) ]; then
  echo "delete cap"
elif [ "$busy" != 0 ]; then
  echo "keep busy"
# A last-busy time in the future (clock step) counts as recent, not idle.
elif [ $((now - last_busy)) -lt $((idle_min * 60)) ]; then
  echo "keep recent"
# Deleting early in an hour saves nothing: the started hour is billed anyway.
elif [ $((age / 60 % 60)) -lt "$hour_min" ]; then
  echo "keep early"
else
  echo "delete idle"
fi
