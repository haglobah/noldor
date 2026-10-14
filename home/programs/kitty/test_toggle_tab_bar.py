"""Tests for the tab bar toggle kitten. Run: python3 -m pytest home/programs/kitty"""
from toggle_tab_bar import toggle


class FakeTabManager:
    def __init__(self, hidden):
        self.tab_bar_hidden = hidden
        self.calls = []

    def mark_tab_bar_dirty(self):
        self.calls.append("dirty")

    def layout_tab_bar(self):
        self.calls.append("layout")

    def resize(self, only_tabs=False):
        self.calls.append(("resize", only_tabs))


def test_hides_a_shown_bar_and_gives_windows_the_space():
    tm = FakeTabManager(hidden=False)
    toggle(tm)
    assert tm.tab_bar_hidden
    assert tm.calls == ["dirty", ("resize", True)]


def test_shows_a_hidden_bar_and_lays_it_out_first():
    tm = FakeTabManager(hidden=True)
    toggle(tm)
    assert not tm.tab_bar_hidden
    assert tm.calls == ["dirty", "layout", ("resize", True)]
