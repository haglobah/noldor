"""Tests for the custom tab title. Run: python3 -m pytest home/programs/kitty"""
import termios

from tab_bar import (
    BLOCKED,
    IDLE,
    RUNNING,
    dir_label,
    format_title,
    git_branch,
    is_password_prompt,
    majority_cwd,
    tab_state,
    window_state,
)

HOME = "/home/beat"


def test_single_dir_shows_last_component():
    assert dir_label(["/home/beat/projects/ht"], "/home/beat/projects/ht", HOME) == "ht"


def test_majority_dir_wins_over_active():
    cwds = ["/home/beat/noldor", "/home/beat/projects/ht", "/home/beat/projects/ht"]
    assert dir_label(cwds, "/home/beat/noldor", HOME) == "ht"


def test_tie_goes_to_active_window():
    cwds = ["/home/beat/noldor", "/home/beat/projects/ht"]
    assert dir_label(cwds, "/home/beat/noldor", HOME) == "noldor"


def test_home_shows_tilde():
    assert dir_label([HOME], HOME, HOME) == "~"


def test_root_shows_slash():
    assert dir_label(["/"], "/", HOME) == "/"


def test_unknown_cwds_are_ignored():
    assert dir_label([None, "/home/beat/noldor"], None, HOME) == "noldor"


def test_no_known_cwd_gives_empty_label():
    assert dir_label([None], None, HOME) == ""


def test_trailing_slash_is_ignored():
    assert dir_label(["/home/beat/noldor/"], None, HOME) == "noldor"


def test_majority_cwd_returns_the_full_path():
    cwds = ["/home/beat/noldor", "/home/beat/projects/ht", "/home/beat/projects/ht"]
    assert majority_cwd(cwds, "/home/beat/noldor") == "/home/beat/projects/ht"


def test_majority_cwd_of_no_known_cwd_is_none():
    assert majority_cwd([None], None) is None


def test_branch_is_read_from_head_of_enclosing_repo(tmp_path):
    (tmp_path / ".git").mkdir()
    (tmp_path / ".git" / "HEAD").write_text("ref: refs/heads/feature/tabs\n")
    (tmp_path / "src").mkdir()
    assert git_branch(str(tmp_path / "src")) == "feature/tabs"


def test_detached_head_shows_short_commit(tmp_path):
    (tmp_path / ".git").mkdir()
    (tmp_path / ".git" / "HEAD").write_text("2e78bfb0123456789abcdef0123456789abcdef0\n")
    assert git_branch(str(tmp_path)) == "2e78bfb"


def test_worktree_branch_is_read_through_gitdir_file(tmp_path):
    gitdir = tmp_path / "main" / ".git" / "worktrees" / "wt"
    gitdir.mkdir(parents=True)
    (gitdir / "HEAD").write_text("ref: refs/heads/wt-branch\n")
    (tmp_path / "wt").mkdir()
    (tmp_path / "wt" / ".git").write_text(f"gitdir: {gitdir}\n")
    assert git_branch(str(tmp_path / "wt")) == "wt-branch"


def test_relative_gitdir_is_resolved_from_the_worktree(tmp_path):
    gitdir = tmp_path / "main" / ".git" / "worktrees" / "wt"
    gitdir.mkdir(parents=True)
    (gitdir / "HEAD").write_text("ref: refs/heads/wt-branch\n")
    (tmp_path / "wt").mkdir()
    (tmp_path / "wt" / ".git").write_text("gitdir: ../main/.git/worktrees/wt\n")
    assert git_branch(str(tmp_path / "wt")) == "wt-branch"


def test_no_repo_has_no_branch(tmp_path):
    assert git_branch(str(tmp_path)) is None


def test_unknown_cwd_has_no_branch():
    assert git_branch(None) is None


def state(title="~/p/ht", at_prompt=False, password_prompt=False, claude_blocked=False):
    return window_state(title, at_prompt, password_prompt, claude_blocked)


def test_shell_prompt_is_idle():
    assert state(at_prompt=True) == IDLE


def test_command_running_is_running():
    assert state("just dev ~/p/media-inbox") == RUNNING


def test_password_prompt_is_blocked():
    assert state("sudo nixos-rebuild", password_prompt=True) == BLOCKED


def test_claude_ready_for_next_prompt_is_idle():
    assert state("✳ Claude Code") == IDLE


def test_claude_asking_a_question_is_blocked():
    assert state("✳ Claude Code", claude_blocked=True) == BLOCKED


def test_working_claude_is_running():
    assert state("◐ Kitty tab title customization") == RUNNING


def test_stale_blocked_flag_is_ignored_while_claude_works():
    assert state("◐ Kitty tab title customization", claude_blocked=True) == RUNNING


def test_codex_ready_for_next_prompt_is_idle():
    assert state("Ready | noldor") == IDLE


def test_working_codex_is_running():
    assert state("Working | noldor") == RUNNING


def test_echo_off_line_mode_is_password_prompt():
    assert is_password_prompt(termios.ICANON)


def test_raw_mode_tui_is_not_password_prompt():
    assert not is_password_prompt(0)


def test_normal_line_mode_is_not_password_prompt():
    assert not is_password_prompt(termios.ICANON | termios.ECHO)


def test_blocked_beats_running_beats_idle():
    assert tab_state([IDLE, RUNNING, BLOCKED]) == BLOCKED
    assert tab_state([IDLE, RUNNING]) == RUNNING
    assert tab_state([IDLE, IDLE]) == IDLE


def test_empty_tab_is_idle():
    assert tab_state([]) == IDLE


RED_BADGE = "\x1b[1;38:2:30:30:46;48:2:243:139:168m"
ORANGE = "\x1b[1;38:2:250:179:135m"
GREEN = "\x1b[1;38:2:166:227:161m"
RESET = "\x1b[22;39;49m"
GRAY = "\x1b[22;38:2:147:153:178m"


def test_blocked_tab_keeps_tab_color_and_ends_in_exclamation_mark_badge():
    assert format_title("noldor", 2, BLOCKED) == f"noldor 2 {RED_BADGE} ! {RESET}"


def test_running_tab_shows_orange_triangle():
    assert format_title("ht", 1, RUNNING) == f"ht 1 {ORANGE}▶{RESET}"


def test_idle_tab_shows_green_circle():
    assert format_title("~", 3, IDLE) == f"~ 3 {GREEN}○{RESET}"


def test_branch_goes_on_a_gray_second_line():
    assert format_title("ht", 1, IDLE, "main") == f"ht 1 {GREEN}○{RESET}\n{GRAY}main{RESET}"
