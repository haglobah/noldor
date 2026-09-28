"""Tests for the custom tab title. Run: python3 -m pytest home/programs/kitty"""
import termios

from tab_bar import BLOCKED, IDLE, RUNNING, dir_label, format_title, is_password_prompt, tab_state, window_state

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


def test_format_title():
    assert format_title("noldor", 2, BLOCKED) == "noldor | 2 | ◆"
