"""Tests for the tab bar toggle kitten. Run: python3 -m pytest home/programs/kitty"""
from toggle_tab_bar import toggle


class FakeTab:
    def __init__(self, name, log):
        self.name, self.log = name, log

    def relayout(self):
        self.log.append(("relayout", self.name))


class FakeTabManager:
    def __init__(self, hidden):
        self.tab_bar_hidden = hidden
        self.calls = []
        self.tabs = [FakeTab(n, self.calls) for n in ("a", "b", "c")]
        self.active_tab = self.tabs[1]

    def mark_tab_bar_dirty(self):
        self.calls.append("dirty")

    def layout_tab_bar(self):
        self.calls.append("layout")


def run(tm):
    deferred = []
    toggle(tm, deferred.append)
    return deferred


def test_hides_a_shown_bar_and_resizes_only_the_visible_tab_at_once():
    tm = FakeTabManager(hidden=False)
    run(tm)
    assert tm.tab_bar_hidden
    assert tm.calls == ["dirty", ("relayout", "b")]


def test_shows_a_hidden_bar_and_lays_it_out_first():
    tm = FakeTabManager(hidden=True)
    run(tm)
    assert not tm.tab_bar_hidden
    assert tm.calls == ["dirty", "layout", ("relayout", "b")]


def test_background_tabs_are_resized_later():
    tm = FakeTabManager(hidden=False)
    (later,) = run(tm)
    tm.calls.clear()
    later()
    assert tm.calls == [("relayout", "a"), ("relayout", "c")]


def test_tab_closed_before_the_deferred_resize_is_skipped():
    tm = FakeTabManager(hidden=False)
    (later,) = run(tm)
    tm.tabs.pop(0)
    tm.calls.clear()
    later()
    assert tm.calls == [("relayout", "c")]
