"""kitty watcher: redraws tab bars so tab_bar.py sees state that fires no kitty event.

Password prompts only change terminal flags, and Claude Code hooks only set a user var.
"""
from kitty.fast_data_types import add_timer


def _refresh(boss):
    for tm in boss.all_tab_managers:
        tm.mark_tab_bar_dirty()


def on_load(boss, data):
    add_timer(lambda timer_id: _refresh(boss), 1.0, True)


def on_set_user_var(boss, window, data):
    _refresh(boss)
