"""kitty kitten: show or hide the tab bar of the current OS window.

kitty has no action for this; it only hides the bar via `tab_bar_style hidden`,
which it stores as TabManager.tab_bar_hidden. This kitten flips that flag.
A config reload resets it to the configured style.

Map with: map <key> kitten toggle_tab_bar.py
"""
def toggle(tm):
    tm.tab_bar_hidden = not tm.tab_bar_hidden
    tm.mark_tab_bar_dirty()
    if not tm.tab_bar_hidden:
        tm.layout_tab_bar()
    tm.resize(only_tabs=True)


def main(args):
    pass


def handle_result(args, answer, target_window_id, boss):
    tm = boss.active_tab_manager
    if tm is not None:
        toggle(tm)


handle_result.no_ui = True
