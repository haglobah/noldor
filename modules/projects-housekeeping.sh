# Removes the git worktrees in ~/projects whose work is on GitHub, and
# strips the regenerable outputs from the stale ones it keeps. See
# ./projects-housekeeping.nix for why and when.
#
# Usage: projects-housekeeping [--dry-run]
# Environment: PROJECTS (default ~/projects), STALE_DAYS (default 3),
# SERVERS_JSON (hotlustre's preview/servers.json, optional).

dry=
[ "${1:-}" = --dry-run ] && dry=1
projects=${PROJECTS:-$HOME/projects}
days=${STALE_DAYS:-3}
servers=${SERVERS_JSON:-}

# Ignored paths (by their last component) that a build or an install makes
# again. Every other ignored file must be identical to the main checkout's
# copy (.env.local, copied in when the worktree was made) for the worktree
# to go; otherwise it is kept and only these are deleted.
regenerable='^(node_modules|dist|dev-dist|build|_build|\.astro|\.next|\.vercel|\.svelte-kit|\.turbo|\.cache|\.parcel-cache|\.vite|coverage|test-results|playwright-report|\.test-data.*|\.tmp|tsconfig\.tsbuildinfo|next-env\.d\.ts)$'

run() {
  if [ -n "$dry" ]; then echo "  would: $*"; else "$@"; fi
}

# The directories processes run in, to leave alone a worktree in use (a dev
# server, an agent's shell, an editor).
cwds=$(for p in /proc/[0-9]*/cwd; do readlink "$p" 2>/dev/null || true; done | sort -u)
in_use() {
  printf '%s\n' "$cwds" | grep -qxF "$1" || printf '%s\n' "$cwds" | grep -qF "$1/"
}

# Touched in the last $days days: a file outside node_modules, or HEAD and
# its reflog (a commit, a checkout, a reset). Not the index or the git dir
# itself: every `git status` (Flow scans them) rewrites those.
touched() {
  [ -n "$(find "$1" \( -name node_modules -o -name .git \) -prune -o -mtime "-$days" -print -quit 2>/dev/null)" ] ||
    [ -n "$(find "$2/HEAD" "$2/logs/HEAD" -mtime "-$days" -print 2>/dev/null)" ]
}

drop_server_entries() {
  local wt=$1 tilde tmp
  [ -n "$servers" ] && [ -f "$servers" ] || return 0
  tilde="~${wt#"$HOME"}"
  jq -e --arg a "$wt" --arg b "$tilde" 'any(.servers[]?; .dir == $a or .dir == $b)' "$servers" >/dev/null || return 0
  if [ -n "$dry" ]; then
    echo "  would: drop its dev servers from $servers"
    return 0
  fi
  tmp=$(mktemp "$servers.XXXXXX")
  jq --arg a "$wt" --arg b "$tilde" '.servers |= map(select(.dir != $a and .dir != $b))' "$servers" >"$tmp"
  chmod --reference="$servers" "$tmp"
  mv "$tmp" "$servers"
}

removed=0
kept=()
mains=()
for wt in "$projects"/*; do
  # Linked worktrees only: their .git is a file. Main clones are never touched.
  [ -f "$wt/.git" ] || continue
  common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  gitdir=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || continue
  main=$(dirname "$common")
  [ -d "$main" ] && [ "$main" != "$wt" ] || continue
  name=$(basename "$wt")

  if in_use "$wt" || touched "$wt" "$gitdir"; then continue; fi
  mains+=("$main")

  reasons=()
  [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || reasons+=("uncommitted changes")
  ahead=$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null || echo "?")
  [ "$ahead" = 0 ] || reasons+=("$ahead commits on no remote")

  regen=()
  unique=()
  while IFS= read -r -d '' entry; do
    [ "${entry:0:2}" = "!!" ] || continue
    path=${entry:3}
    path=${path%/}
    if [[ "$(basename "$path")" =~ $regenerable ]]; then
      regen+=("$path")
    elif ! diff -rq "$wt/$path" "$main/$path" >/dev/null 2>&1; then
      unique+=("$path")
    fi
  done < <(git -C "$wt" status --porcelain=v1 -z --ignored=matching --untracked-files=normal 2>/dev/null)
  [ ${#unique[@]} = 0 ] || reasons+=("ignored files of its own: ${unique[*]}")

  if [ ${#reasons[@]} = 0 ]; then
    echo "remove $name"
    drop_server_entries "$wt"
    run git -C "$main" worktree remove --force "$wt"
    removed=$((removed + 1))
  else
    kept+=("$name ($(IFS=';'; echo "${reasons[*]}"))")
    if [ ${#regen[@]} -gt 0 ]; then
      echo "strip $name: ${regen[*]}"
      for path in "${regen[@]}"; do run rm -rf "${wt:?}/$path"; done
    fi
  fi
done

if [ ${#mains[@]} -gt 0 ]; then
  for main in $(printf '%s\n' "${mains[@]}" | sort -u); do
    run git -C "$main" worktree prune
  done
fi

echo "$removed worktrees removed, ${#kept[@]} stale ones kept:"
for k in "${kept[@]}"; do echo "  $k"; done
