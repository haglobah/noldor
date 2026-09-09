"""Tests for the balance_splits kitten. Run: python3 -m pytest home/programs/kitty"""
from balance_splits import balance


class Pair:
    """Minimal stand-in for kitty.layout.splits.Pair."""

    def __init__(self, horizontal, one, two, bias=0.5):
        self.horizontal, self.one, self.two, self.bias = horizontal, one, two, bias


def test_two_columns_stay_half():
    root = Pair(True, 1, 2, bias=0.2)
    balance(root)
    assert root.bias == 0.5


def test_three_columns_right_nested():
    inner = Pair(True, 2, 3, bias=0.7)
    root = Pair(True, 1, inner, bias=0.5)
    balance(root)
    assert root.bias == 1 / 3
    assert inner.bias == 0.5


def test_three_columns_left_nested():
    inner = Pair(True, 1, 2, bias=0.1)
    root = Pair(True, inner, 3, bias=0.5)
    balance(root)
    assert root.bias == 2 / 3
    assert inner.bias == 0.5


def test_vertical_stack_counts_as_one_column():
    stack = Pair(False, 2, 3, bias=0.9)
    root = Pair(True, 1, stack, bias=0.1)
    balance(root)
    assert root.bias == 0.5
    assert stack.bias == 0.5


def test_stack_with_wide_child_counts_its_widest_row():
    # A | (B over (C | D)): the right side needs two columns for C and D.
    cd = Pair(True, 3, 4, bias=0.3)
    stack = Pair(False, 2, cd, bias=0.3)
    root = Pair(True, 1, stack, bias=0.5)
    balance(root)
    assert root.bias == 1 / 3
    assert stack.bias == 0.5
    assert cd.bias == 0.5


def test_single_child_pair_is_left_alone():
    root = Pair(True, 1, None, bias=0.3)
    balance(root)
    assert root.bias == 0.3
