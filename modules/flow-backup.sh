# Pushes Flow's repositories to GitHub without ever forcing a real ref, and
# without letting one ref that GitHub refuses hold up the rest. See
# ./flow-backup.nix for why.
#
# Usage: flow-backup REPO PREFIX... [-- REPO PREFIX...]
#   e.g. flow-backup ~/projects/hotlustre refs/heads -- repo.git refs/heads refs/versions
# Each PREFIX/* is pushed to the same names on the repository's origin.
# Environment: STATE_DIRECTORY (default ~/.local/state/flow-backup),
# NTFY_TOPIC (unset: only log), NTFY_SERVER (default https://ntfy.sh).

state=${STATE_DIRECTORY:-$HOME/.local/state/flow-backup}
server=${NTFY_SERVER:-https://ntfy.sh}
host=$(uname -n)
host=${host%%.*}
mkdir -p "$state"

failed=0
failed_repos=()
diverged=() # REPO<TAB>REF

# The branches checked out in some worktree of the repository.
checked_out() {
  git -C "$1" worktree list --porcelain | while IFS= read -r line; do
    case $line in "branch "*) echo "${line#branch }" ;; esac
  done
}

# Returns non-zero when a push or fetch itself failed.
backup_repo() {
  local repo=$1 prefix out rc line spec ref ours theirs backup busy
  shift
  local specs=() rejected=()
  for prefix in "$@"; do specs+=("$prefix/*:$prefix/*"); done

  # Never forced: GitHub refuses what would drop its commits, ref by ref.
  rc=0
  out=$(git -C "$repo" push --porcelain origin "${specs[@]}" 2>&1) || rc=$?
  while IFS= read -r line; do
    [[ $line == $'!\t'* ]] || continue
    IFS=$'\t' read -r _ spec _ <<<"$line"
    rejected+=("${spec%%:*}")
  done <<<"$out"
  if [ "$rc" != 0 ] && [ ${#rejected[@]} = 0 ]; then
    echo "$repo: push failed:"
    printf '%s\n' "$out" | sed 's/^/  /'
    return 1
  fi
  if [ ${#rejected[@]} = 0 ]; then
    echo "$repo: pushed"
    return 0
  fi

  busy=$(checked_out "$repo")
  for ref in "${rejected[@]}"; do
    if ! ours=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}"); then
      echo "$repo $ref: rejected, and not a commit here"
      return 1
    fi
    if ! git -C "$repo" fetch --quiet --no-tags origin "$ref" ||
      ! theirs=$(git -C "$repo" rev-parse --verify --quiet "FETCH_HEAD^{commit}"); then
      echo "$repo $ref: rejected, and fetching GitHub's $ref failed"
      return 1
    fi
    if [ "$ours" = "$theirs" ]; then
      echo "$repo $ref: rejected, but GitHub has it by now"
    elif git -C "$repo" merge-base --is-ancestor "$ours" "$theirs"; then
      # Another machine pushed on top: nothing of ours is lost.
      if printf '%s\n' "$busy" | grep -qxF "$ref"; then
        echo "$repo $ref: GitHub is ahead ($theirs); checked out here, so left as it is"
      elif git -C "$repo" update-ref "$ref" "$theirs" "$ours"; then
        echo "$repo $ref: GitHub is ahead; fast-forwarded to $theirs"
      else
        echo "$repo $ref: GitHub is ahead; it moved here meanwhile, left as it is"
      fi
    else
      backup="refs/backup/$host/${ref#refs/}"
      if ! git -C "$repo" push --quiet --force origin "$ours:$backup"; then
        echo "$repo $ref: diverged from GitHub ($theirs), and pushing ours to $backup failed"
        return 1
      fi
      echo "$repo $ref: diverged from GitHub ($theirs); ours ($ours) is on GitHub as $backup"
      diverged+=("$repo"$'\t'"$ref")
    fi
  done
}

group=()
run_group() {
  [ ${#group[@]} -gt 0 ] || return 0
  if ! backup_repo "${group[@]}"; then
    failed=1
    failed_repos+=("${group[0]}")
  fi
  group=()
}
for arg in "$@"; do
  if [ "$arg" = -- ]; then run_group; else group+=("$arg"); fi
done
run_group

# The set of diverged refs. A repository that failed this time keeps what the
# last run knew of it, so an outage does not read as "resolved".
before=$(sed '/^$/d' "$state/diverged" 2>/dev/null | sort -u || true)
now=$(
  printf '%s\n' "${diverged[@]}"
  while IFS=$'\t' read -r repo ref; do
    for r in "${failed_repos[@]}"; do
      if [ "$repo" = "$r" ]; then printf '%s\t%s\n' "$repo" "$ref"; fi
    done
  done <<<"$before"
)
now=$(printf '%s\n' "$now" | sed '/^$/d' | sort -u)

notify() {
  if [ -z "${NTFY_TOPIC:-}" ]; then
    echo "not notifying, NTFY_TOPIC is unset: $1"
    return 0
  fi
  curl -fsS --max-time 30 -o /dev/null \
    -H "Title: $1" -H "Priority: 3" -H "Tags: floppy_disk" \
    -d "$2" "$server/$NTFY_TOPIC" && echo "notified: $1"
}

if [ "$now" != "$before" ]; then
  if [ -n "$now" ]; then
    names=$(printf '%s\n' "$now" | cut -f2 | sed 's|^refs/heads/||; s|^refs/||' | sort -u | paste -sd, - | sed 's/,/, /g')
    title="$host: flow-backup: $names diverged from GitHub"
    message="GitHub rejected these, and it and $host each have commits the other lacks. Nothing is lost: ours is on GitHub under refs/backup/$host/, kept up to date each run."
    while IFS=$'\t' read -r repo ref; do
      message+=$'\n\n'"$repo $ref -> refs/backup/$host/${ref#refs/}"$'\n'"See: git -C $repo fetch origin $ref && git -C $repo log --oneline --graph $ref FETCH_HEAD"
    done <<<"$now"
    message+=$'\n\n'"To reconcile, start an agent on it: merge or rebase, push, and delete the backup ref."
  else
    title="$host: flow-backup: resolved, nothing diverged"
    message="Every ref that had diverged from GitHub is pushed again (or gone). Leftover refs/backup/$host/* on GitHub can be deleted: git push origin --delete refs/backup/$host/..."
  fi
  if notify "$title" "$message"; then
    printf '%s\n' "$now" >"$state/diverged.tmp"
    mv "$state/diverged.tmp" "$state/diverged"
  else
    echo "notifying failed; trying again next run"
  fi
fi

exit "$failed"
