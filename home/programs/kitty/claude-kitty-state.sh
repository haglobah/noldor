# Claude Code hook: marks this kitty window as blocked while Claude waits on a
# question or permission dialog, so the tab bar can show it (see tab_bar.py).
# Usage: claude-kitty-state blocked|clear
[ -n "${KITTY_WINDOW_ID:-}" ] && [ -n "${KITTY_LISTEN_ON:-}" ] || exit 0
case "${1:-}" in
  blocked) var=claude_state=blocked ;;
  *) var=claude_state ;;
esac
# A hook must never fail Claude's turn because kitty is unreachable.
kitten @ --to "$KITTY_LISTEN_ON" set-user-vars --match "id:$KITTY_WINDOW_ID" "$var" >/dev/null 2>&1 || true
