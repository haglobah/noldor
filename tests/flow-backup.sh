# Test of flow-backup (modules/flow-backup.sh), run by tests/flow-backup.nix
# with the built command and a fake curl (logging to $CURL_LOG) on PATH.
# A bare "github" per repository; "checkout" is a clone with a linked
# worktree (as ~/projects/hotlustre), "versions" a bare repo (repo.git).
set -euo pipefail
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git() { command git -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }

t=$(mktemp -d)
export STATE_DIRECTORY=$t/state NTFY_TOPIC=topic CURL_LOG=$t/curl.log
: >"$CURL_LOG"
host=$(uname -n)
host=${host%%.*}
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

git init -q --bare "$t/gh-hotlustre.git"
git init -q --bare "$t/gh-versions.git"
git clone -q "$t/gh-hotlustre.git" "$t/checkout"
git -C "$t/checkout" commit -q --allow-empty -m one
git -C "$t/checkout" branch side
git -C "$t/checkout" branch other
git -C "$t/checkout" worktree add -q "$t/wt-other" other
git init -q --bare "$t/versions.git"
git -C "$t/versions.git" remote add origin "$t/gh-versions.git"
v1=$(git -C "$t/checkout" commit-tree -m v1 "$(git -C "$t/checkout" write-tree)")
git -C "$t/checkout" push -q "$t/versions.git" "$v1:refs/heads/main" "$v1:refs/versions/v0001"
# Another machine: a clone of GitHub's hotlustre.
other() { git -C "$t/laptop" "$@"; }

run() {
  out=$(flow-backup "$t/checkout" refs/heads -- "$t/versions.git" refs/heads refs/versions 2>&1) && rc=0 || rc=$?
  printf '%s\n' "$out" | sed 's/^/     | /'
}
gh() { git -C "$t/gh-$1.git" rev-parse --verify --quiet "$2" || echo none; }
here() { git -C "$t/checkout" rev-parse "$1"; }
posts() { grep -c . "$CURL_LOG" || true; }

echo "== everything pushes"
run
check "exit 0" '[ $rc = 0 ]'
check "main, side, other on GitHub" '[ "$(gh hotlustre main)" = "$(here main)" ] && [ "$(gh hotlustre side)" = "$(here side)" ] && [ "$(gh hotlustre other)" = "$(here other)" ]'
check "versions on GitHub" '[ "$(gh versions refs/versions/v0001)" = "$v1" ] && [ "$(gh versions main)" = "$v1" ]'
check "no post" '[ "$(posts)" = 0 ]'

echo "== GitHub ahead on the checked-out main and the side branch; new local version"
git clone -q "$t/gh-hotlustre.git" "$t/laptop"
other checkout -q main && other commit -q --allow-empty -m laptop-main && other push -q origin main
other checkout -q side && other commit -q --allow-empty -m laptop-side && other push -q origin side
main_before=$(here main)
echo dirty >"$t/checkout/wip"
v2=$(git -C "$t/checkout" commit-tree -p "$v1" -m v2 "$(git -C "$t/checkout" write-tree)")
git -C "$t/checkout" push -q -f "$t/versions.git" "$v2:refs/versions/v0002"
run
check "exit 0" '[ $rc = 0 ]'
check "checked-out main left as it is" '[ "$(here main)" = "$main_before" ] && [ "$(git -C "$t/checkout" rev-parse HEAD)" = "$main_before" ]'
check "working tree untouched" '[ "$(cat "$t/checkout/wip")" = dirty ] && [ -z "$(git -C "$t/checkout" status --porcelain --untracked-files=no)" ]'
check "GitHub's main not forced back" '[ "$(gh hotlustre main)" = "$(other rev-parse main)" ]'
check "side fast-forwarded to GitHub's" '[ "$(here side)" = "$(other rev-parse side)" ]'
check "the other repo still pushed" '[ "$(gh versions refs/versions/v0002)" = "$v2" ]'
check "no backup refs" '[ -z "$(git -C "$t/gh-hotlustre.git" for-each-ref refs/backup)" ]'
check "no post" '[ "$(posts)" = 0 ]'

echo "== the linked worktree's branch: GitHub ahead, left as it is"
other checkout -q other && other commit -q --allow-empty -m laptop-other && other push -q origin other
other_before=$(here other)
run
check "exit 0" '[ $rc = 0 ]'
check "other (checked out in a worktree) left as it is" '[ "$(here other)" = "$other_before" ]'

echo "== main diverged"
git -C "$t/checkout" commit -q --allow-empty -m cirdan-main
ours=$(here main)
theirs=$(gh hotlustre main)
run
check "exit 0" '[ $rc = 0 ]'
check "GitHub's main untouched" '[ "$(gh hotlustre main)" = "$theirs" ]'
check "ours on GitHub as refs/backup/$host/heads/main" '[ "$(gh hotlustre "refs/backup/$host/heads/main")" = "$ours" ]'
check "one post" '[ "$(posts)" = 1 ]'
check "post's title names main" 'grep -q "Title: $host: flow-backup: main diverged from GitHub" "$CURL_LOG"'
check "post goes to ntfy.sh/topic at priority 3" 'grep -q "https://ntfy.sh/topic" "$CURL_LOG" && grep -q "Priority: 3" "$CURL_LOG"'
run
check "second run: exit 0" '[ $rc = 0 ]'
check "second run: no new post" '[ "$(posts)" = 1 ]'
git -C "$t/checkout" commit -q --allow-empty -m cirdan-main-2
run
check "ours moved on: backup ref follows" '[ "$(gh hotlustre "refs/backup/$host/heads/main")" = "$(here main)" ]'
check "ours moved on: no new post" '[ "$(posts)" = 1 ]'

echo "== a version ref diverges too"
v3a=$(git -C "$t/checkout" commit-tree -p "$v2" -m v3a "$(git -C "$t/checkout" write-tree)")
v3b=$(git -C "$t/checkout" commit-tree -p "$v2" -m v3b "$(git -C "$t/checkout" write-tree)")
git -C "$t/checkout" push -q "$t/gh-versions.git" "$v3a:refs/versions/v0003"
git -C "$t/checkout" push -q "$t/versions.git" "$v3b:refs/versions/v0003"
run
check "exit 0" '[ $rc = 0 ]'
check "ours on GitHub as refs/backup/$host/versions/v0003" '[ "$(gh versions "refs/backup/$host/versions/v0003")" = "$v3b" ]'
check "a second post, naming both" '[ "$(posts)" = 2 ] && tail -1 "$CURL_LOG" | grep -q "main, versions/v0003 diverged"'

echo "== fetch fails (GitHub unreachable for fetches, reachable for pushes)"
git -C "$t/checkout" remote set-url origin "$t/nowhere.git"
git -C "$t/checkout" remote set-url --push origin "$t/gh-hotlustre.git"
v4=$(git -C "$t/checkout" commit-tree -p "$v2" -m v4 "$(git -C "$t/checkout" write-tree)")
git -C "$t/checkout" push -q -f "$t/versions.git" "$v4:refs/versions/v0004"
run
check "exit non-zero" '[ $rc != 0 ]'
check "the other repo still pushed" '[ "$(gh versions refs/versions/v0004)" = "$v4" ]'
check "no 'resolved' post for the unreachable repo" '[ "$(posts)" = 2 ]'
git -C "$t/checkout" remote set-url origin "$t/gh-hotlustre.git"
git -C "$t/checkout" config --unset remote.origin.pushurl

echo "== push fails (GitHub gone)"
mv "$t/gh-versions.git" "$t/gh-versions.gone"
run
check "exit non-zero" '[ $rc != 0 ]'
mv "$t/gh-versions.gone" "$t/gh-versions.git"

echo "== resolved"
git -C "$t/checkout" fetch -q origin
git -C "$t/checkout" merge -q --no-edit origin/main
git -C "$t/checkout" push -q -f "$t/versions.git" "$v3a:refs/versions/v0003"
run
check "exit 0" '[ $rc = 0 ]'
check "main on GitHub is the merge" '[ "$(gh hotlustre main)" = "$(here main)" ]'
check "one 'resolved' post" '[ "$(posts)" = 3 ] && tail -1 "$CURL_LOG" | grep -q "resolved, nothing diverged"'
run
check "no more posts" '[ "$(posts)" = 3 ]'

echo "== NTFY_TOPIC unset: only logged"
git -C "$t/checkout" commit -q --allow-empty -m again
other checkout -q main && other pull -q --no-rebase origin main && other commit -q --allow-empty -m again-laptop && other push -q origin main
NTFY_TOPIC='' run
check "exit 0, no post, logged" '[ $rc = 0 ] && [ "$(posts)" = 3 ] && printf "%s" "$out" | grep -q "NTFY_TOPIC is unset"'

exit "$fail"
