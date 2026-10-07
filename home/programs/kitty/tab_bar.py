"""Custom tab title: majority working directory, window count, state.

kitty calls draw_title() for `{custom}` in tab_title_template.
"""
import os
import termios
from collections import Counter

IDLE, RUNNING, BLOCKED = "idle", "running", "blocked"
# Bold SGR and text per state, in Catppuccin Mocha colors. Blocked is a
# badge: base-colored "!" on red, since terminal cells cannot have borders.
ICONS = {
    IDLE: ("1;38:2:166:227:161", "○"),
    RUNNING: ("1;38:2:250:179:135", "▶"),
    BLOCKED: ("1;38:2:30:30:46;48:2:243:139:168", " ! "),
}
# Claude Code prefixes its title with ✳ while it waits for input
# and with a spinner character while it works.
CLAUDE_WAITING_PREFIX = "✳"
# Set by Claude Code hooks while a question or permission dialog is open,
# see claude-kitty-state.sh. The title alone cannot tell this apart from ✳.
CLAUDE_STATE_VAR = "claude_state"
# Codex leads its title with its run state, see tui.terminal_title in
# pkgs/codex. It shows "Working" during approval prompts too.
CODEX_READY_PREFIX = "Ready | "


def dir_label(cwds, active_cwd, home):
    """Last path component of the most common cwd; ties go to the active window."""
    counts = Counter(os.path.normpath(c) for c in cwds if c)
    if not counts:
        return ""
    top = max(counts.values())
    candidates = [c for c, n in counts.items() if n == top]
    active = os.path.normpath(active_cwd) if active_cwd else None
    path = active if active in candidates else candidates[0]
    if path == os.path.normpath(home):
        return "~"
    return os.path.basename(path) or path


def is_password_prompt(lflag):
    """sudo, su, ssh and getpass turn echo off but keep line mode; TUIs turn both off."""
    return bool(lflag & termios.ICANON) and not lflag & termios.ECHO


def window_state(title, at_prompt, password_prompt, claude_blocked):
    if password_prompt:
        return BLOCKED
    if title.startswith(CLAUDE_WAITING_PREFIX):
        return BLOCKED if claude_blocked else IDLE
    if title.startswith(CODEX_READY_PREFIX):
        return IDLE
    return IDLE if at_prompt else RUNNING


def tab_state(states):
    for state in (BLOCKED, RUNNING):
        if state in states:
            return state
    return IDLE


def format_title(label, num_windows, state):
    """kitty applies SGR escapes in the title and resets them after each tab."""
    sgr, icon = ICONS[state]
    return f"{label} {num_windows} \x1b[{sgr}m{icon}\x1b[22;39;49m"


def draw_title(data):
    from kitty.fast_data_types import get_boss

    tab = get_boss().tab_for_id(data["tab_id"])
    if tab is None:
        return data["title"]
    windows = list(tab)
    active = tab.active_window
    label = dir_label(
        [w.cwd_of_child for w in windows],
        active.cwd_of_child if active else None,
        os.path.expanduser("~"),
    )
    state = tab_state([_live_window_state(w) for w in windows])
    return format_title(label, len(windows), state)


def _live_window_state(w):
    try:
        password_prompt = is_password_prompt(termios.tcgetattr(w.child.child_fd)[3])
    except (termios.error, TypeError):  # child already exited
        password_prompt = False
    claude_blocked = w.user_vars.get(CLAUDE_STATE_VAR) == BLOCKED
    return window_state(w.title, w.at_prompt, password_prompt, claude_blocked)
