# Unit test of aule's self-deletion decision (modules/nix-builder/reap-decide.sh).
# Times are Unix seconds; the server was created at t=0.
{ pkgs }:
let
  decide = pkgs.callPackage ../modules/nix-builder/reap-decide.nix { };
in
pkgs.runCommand "nix-builder-reaper" { nativeBuildInputs = [ decide ]; } ''
  fail=0
  # expect <wanted output> <now> <created> <last-busy> <busy>
  expect() {
    got=$(reap-decide "$2" "$3" "$4" "$5")
    if [ "$got" = "$1" ]; then
      echo "ok   $1 <- now=$2 created=$3 last-busy=$4 busy=$5"
    else
      echo "FAIL want '$1', got '$got' <- now=$2 created=$3 last-busy=$4 busy=$5"
      fail=1
    fi
  }
  m=60

  # A build is running: keep, even late in the hour and long idle before.
  expect "keep busy"        $((55 * m))  0 0             1
  # Idle 20 min, but only 30 min into the billed hour: the hour is paid anyway.
  expect "keep early"       $((30 * m))  0 $((10 * m))   0
  # 55 min into the hour, but the last build ended 5 min ago.
  expect "keep recent"      $((55 * m))  0 $((50 * m))   0
  # Idle 15 min, 55 min into the first hour: delete before the next hour starts.
  expect "delete idle"      $((55 * m))  0 $((40 * m))   0
  # Same in the third hour: minute 50 of hour 3 counts, not minute 170.
  expect "delete idle"      $((170 * m)) 0 $((100 * m))  0
  # Second hour, minute 20: keep.
  expect "keep early"       $((80 * m))  0 $((10 * m))   0
  # Exactly at the thresholds: idle 10 min, minute 50.
  expect "delete idle"      $((50 * m))  0 $((40 * m))   0
  # Over the 6 h cap: delete even while busy.
  expect "delete cap"       $((360 * m)) 0 $((360 * m))  1
  expect "delete cap"       $((400 * m)) 0 0             0
  # Clock skew (last busy in the future) counts as busy, not as idle.
  expect "keep recent"      $((55 * m))  0 $((60 * m))   0

  # Malformed input must not be read as "idle"; it fails loudly.
  if reap-decide 100 abc 0 0 >/dev/null 2>&1; then
    echo "FAIL non-numeric input was accepted"; fail=1
  else
    echo "ok   non-numeric input rejected"
  fi

  [ "$fail" = 0 ] && touch $out
''
