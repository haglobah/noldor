"""kitty kitten: show or hide the tab bar of the current OS window.

kitty has no action for this; it only hides the bar via `tab_bar_style hidden`,
which it stores as TabManager.tab_bar_hidden. This kitten flips that flag.
A config reload resets it to the configured style.

Map with: map <key> kitten toggle_tab_bar.py
"""
# Background tabs are resized after this delay, so that their programs do not
# compete for CPU with the visible one while it redraws.
BACKGROUND_RESIZE_DELAY = 0.1


def toggle(tm, defer):
    """defer(fn) schedules fn to run once, later."""
    tm.tab_bar_hidden = not tm.tab_bar_hidden
    tm.mark_tab_bar_dirty()
    if not tm.tab_bar_hidden:
        tm.layout_tab_bar()
    visible = tm.active_tab
    visible.relayout()

    def resize_background_tabs():
        # The OS window may have closed in the meantime.
        for tab in getattr(tm, "tabs", ()):
            if tab is not visible:
                tab.relayout()

    defer(resize_background_tabs)


def main(args):
    pass


def handle_result(args, answer, target_window_id, boss):
    from kitty.fast_data_types import add_timer

    tm = boss.active_tab_manager
    if tm is not None and tm.active_tab is not None:
        toggle(tm, lambda fn: add_timer(lambda timer_id: fn(), BACKGROUND_RESIZE_DELAY, False))


handle_result.no_ui = True
