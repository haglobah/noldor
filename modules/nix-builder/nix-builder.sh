# nix-builder up|down|status|warm FLAKE...|snapshot|sync
#
# Creates and deletes aule, the nix-builds build machine, from its newest
# snapshot. The scheduler on orthanc starts it for builds; gondor uses this
# for snapshots and `clan machines update aule`. See docs/nix-builder.md. Set by the Nix wrapper:
# token_file, ssh_config.

name=aule
selector=machine=$name
# CX53 (16 shared vCPU, 32 GB) is cheap but often sold out; CCX33 (8
# dedicated vCPU, 32 GB) costs ~4.7x as much per hour.
types=(cx53 ccx33)
locations=(fsn1 nbg1)

if [ ! -r "$token_file" ]; then
  echo "nix-builder: cannot read the Hetzner token at $token_file" >&2
  echo "  run 'clan vars generate gondor -g hcloud-token' and deploy gondor" >&2
  exit 1
fi
HCLOUD_TOKEN=$(<"$token_file")
export HCLOUD_TOKEN

# The server as JSON, or nothing if it does not exist. API errors abort.
server_json() {
  hcloud server list --selector "$selector" -o json | jq -c --arg n "$name" 'map(select(.name == $n)) | first // empty'
}

# Newest snapshot first, one id per line.
snapshots() {
  hcloud image list --type snapshot --selector "$selector" -o json | jq -r 'sort_by(.created) | reverse | .[].id'
}

# gondor's /etc/ssh/ssh_config includes this file. Atomic, so a concurrent
# ssh never reads half of it.
write_ssh_config() {
  local tmp
  tmp=$(mktemp "$ssh_config.XXXXXX")
  printf 'Host %s\n  HostName %s\n' "$name" "$1" > "$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$ssh_config"
}

forget_address() {
  if [ -e "$ssh_config" ]; then
    rm -f "$ssh_config"
    echo "removed $ssh_config"
  fi
}

describe() {
  jq -r '"\(.name): \(.status), \(.server_type.name) in \(.location.name), \(.public_net.ipv4.ip), created \(.created)"' <<< "$1"
}

hourly_price() {
  hcloud server-type describe "$1" -o json \
    | jq -r --arg l "$2" '.prices[] | select(.location == $l) | "\(.price_hourly.gross | tonumber * 10000 | round / 10000) EUR/h gross"'
}

cmd_up() {
  local server image type location ip created=""
  server=$(server_json)
  if [ -n "$server" ]; then
    echo "already exists: $(describe "$server")"
  else
    image=$(snapshots | head -n1)
    if [ -z "$image" ]; then
      echo "nix-builder: no snapshot labelled $selector; bootstrap first (docs/nix-builder.md)" >&2
      exit 1
    fi
    for type in "${types[@]}"; do
      for location in "${locations[@]}"; do
        echo "creating $name: $type in $location from snapshot $image"
        if hcloud server create --name "$name" --type "$type" --location "$location" \
          --image "$image" --label "$selector" > /dev/null; then
          created=1
          break 2
        fi
      done
    done
    if [ -z "$created" ]; then
      echo "nix-builder: no server type of ${types[*]} was available in ${locations[*]}" >&2
      exit 1
    fi
    server=$(server_json)
  fi

  ip=$(jq -r '.public_net.ipv4.ip' <<< "$server")
  write_ssh_config "$ip"

  echo "waiting for ssh on $ip"
  for _ in $(seq 60); do
    if timeout 3 bash -c "exec 3<>/dev/tcp/$ip/22" 2> /dev/null; then
      echo "up: $(describe "$server")"
      echo "price: $(hourly_price "$(jq -r '.server_type.name' <<< "$server")" "$(jq -r '.location.name' <<< "$server")")"
      echo "aule deletes itself near the end of an hour after 10 min without builds."
      return 0
    fi
    sleep 5
  done
  echo "nix-builder: $ip:22 did not open within 5 min; the server still bills. 'just builder-down' deletes it." >&2
  exit 1
}

cmd_down() {
  if [ -n "$(server_json)" ]; then
    hcloud server delete "$name"
  else
    echo "$name does not exist"
  fi
  forget_address
}

cmd_status() {
  local server created
  server=$(server_json)
  if [ -n "$server" ]; then
    describe "$server"
    created=$(date -d "$(jq -r .created <<< "$server")" +%s)
    echo "age: $((($(date +%s) - created) / 60)) min (billed per started hour)"
  else
    echo "$name does not exist"
  fi
  echo "snapshots ($selector):"
  hcloud image list --type snapshot --selector "$selector" -o columns=id,created,image_size,disk_size,description
  if [ -e "$ssh_config" ]; then
    echo "$ssh_config:"
    sed 's/^/  /' "$ssh_config"
  else
    echo "$ssh_config: absent"
  fi
}

# Realise the build inputs of each flake's buildJobs on the running aule,
# so a server made from the next snapshot doesn't download them again for
# every build. Evaluates here: aule cannot read the private repos. Only the
# inputs (inputDerivation), not the outputs: an output already in aule's
# store never runs the post-build hook, so it would never reach R2.
cmd_warm() {
  local flake json drvs=()
  if [ -z "$(server_json)" ]; then
    echo "nix-builder: $name does not exist; run 'nix-builder up' first" >&2
    exit 1
  fi
  for flake in "$@"; do
    echo "evaluating $flake"
    json=$(nix eval --json "$flake#buildJobs.x86_64-linux" \
      --apply 'jobs: map (d: d.inputDerivation.drvPath) (builtins.attrValues jobs)')
    mapfile -t -O "${#drvs[@]}" drvs < <(jq -r '.[]' <<< "$json")
  done
  [ "${#drvs[@]}" -gt 0 ] || return 0
  nix copy --derivation --to "ssh-ng://root@$name" "${drvs[@]}"
  nix build --store "ssh-ng://root@$name" --no-link -L "${drvs[@]/%/^out}"
}

# Snapshot the running aule, keep only the new snapshot, delete the server.
cmd_snapshot() {
  local id
  if [ -z "$(server_json)" ]; then
    echo "nix-builder: $name does not exist; run 'nix-builder up' first" >&2
    exit 1
  fi
  # The deploy's own build queued aule's system for upload. Left in the
  # snapshot, every new aule would retry that entry at boot.
  ssh "root@$name" 'rm -f /var/lib/nix-cache-push/queue/*'
  # Powered off, the disk is consistent; snapshotting a running server is
  # allowed but may catch half-written files.
  hcloud server shutdown --wait --wait-timeout 3m "$name"
  hcloud server create-image --type snapshot --label "$selector" \
    --description "$name $(date -u +%Y-%m-%dT%H:%MZ)" "$name"
  mapfile -t old < <(snapshots | tail -n +2)
  for id in "${old[@]}"; do
    echo "deleting older snapshot $id"
    hcloud image delete "$id"
  done
  cmd_down
}

# Run by nix-builder-sync.timer: aule deletes itself without telling gondor,
# and a stale address would point `clan machines update aule` at a stranger. Only asks the API while an address is recorded.
cmd_sync() {
  local server ip
  [ -e "$ssh_config" ] || return 0
  server=$(server_json)
  if [ -z "$server" ]; then
    echo "$name is gone"
    forget_address
    return 0
  fi
  ip=$(jq -r '.public_net.ipv4.ip' <<< "$server")
  if ! grep -qxF "  HostName $ip" "$ssh_config"; then
    echo "$name moved to $ip"
    write_ssh_config "$ip"
  fi
}

case "${1:-}" in
  up | down | status | snapshot | sync) "cmd_$1" ;;
  warm)
    shift
    cmd_warm "$@"
    ;;
  *)
    echo "usage: nix-builder up|down|status|warm FLAKE...|snapshot|sync" >&2
    exit 1
    ;;
esac
