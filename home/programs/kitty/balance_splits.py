"""kitty kitten: give every column (and row) of the splits layout equal size.

`resize_window reset` sets every split to 50/50, which for the tree A | (B | C)
gives 1/2 | 1/4 | 1/4. This kitten weights each split by the number of
columns (or rows) on each side, so A | (B | C) becomes 1/3 | 1/3 | 1/3.

Map with: map <key> kitten balance_splits.py
"""


def is_pair(node):
    return hasattr(node, 'one') and hasattr(node, 'two')


def units(node, horizontal):
    """Columns (horizontal=True) or rows (False) that `node` needs."""
    if node is None:
        return 0
    if not is_pair(node):
        return 1
    a, b = units(node.one, horizontal), units(node.two, horizontal)
    if node.horizontal == horizontal:
        return a + b
    return max(a, b)


def balance(pair):
    for child in (pair.one, pair.two):
        if is_pair(child):
            balance(child)
    a, b = units(pair.one, pair.horizontal), units(pair.two, pair.horizontal)
    if a and b:
        pair.bias = a / (a + b)


def main(args):
    pass


def handle_result(args, answer, target_window_id, boss):
    tab = boss.active_tab
    if tab is None:
        return
    root = getattr(tab.current_layout, 'pairs_root', None)
    if root is None:
        return  # not the splits layout
    balance(root)
    tab.relayout()


handle_result.no_ui = True
