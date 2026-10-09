import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'home/pkgs/screen-above/screen_above.py'
spec = importlib.util.spec_from_file_location('screen_above', SCRIPT)
screen_above = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screen_above)

LOGICAL = 1
PHYSICAL = 2


def mode(width, height, current=False, preferred=False, scale=1.0):
    props = {}
    if current:
        props['is-current'] = True
    if preferred:
        props['is-preferred'] = True
    return (f'{width}x{height}@60.000', width, height, 60.0, scale, [1.0, 2.0], props)


def monitor(connector, modes, builtin=False):
    return ((connector, 'VND', 'Product', '0x1'), modes, {'is-builtin': builtin})


def logical(x, y, scale, connectors, primary=False, transform=0):
    specs = [(c, 'VND', 'Product', '0x1') for c in connectors]
    return (x, y, scale, transform, primary, specs, {})


def state(monitors, logical_monitors, layout_mode=LOGICAL):
    return (1, monitors, logical_monitors, {'layout-mode': layout_mode})


LAPTOP = monitor('eDP-1', [mode(2560, 1600, current=True, preferred=True)], builtin=True)


def placement(args, connector):
    """Return (x, y, primary) of the logical monitor holding connector."""
    start = args.index(connector) - 1
    while args[start] != '--logical-monitor':
        start -= 1
    end = args.index('--logical-monitor', start + 1) if '--logical-monitor' in args[start + 1:] else len(args)
    block = args[start:end]
    return int(block[block.index('--x') + 1]), int(block[block.index('--y') + 1]), '--primary' in block


class PlanTests(unittest.TestCase):
    def test_wide_external_sits_above_centered_laptop(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(3440, 1440, current=True)])],
            [logical(0, 0, 1.0, ['eDP-1'], primary=True), logical(2560, 0, 1.0, ['DP-3'])],
        ))
        self.assertEqual(args[:2], ['set', '--persistent'])
        self.assertEqual(placement(args, 'DP-3'), (0, 0, False))
        self.assertEqual(placement(args, 'eDP-1'), (440, 1440, True))

    def test_narrow_external_is_centered_over_laptop(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(1920, 1080, current=True)])],
            [logical(0, 0, 1.0, ['eDP-1'], primary=True), logical(2560, 0, 1.0, ['DP-3'])],
        ))
        self.assertEqual(placement(args, 'DP-3'), (320, 0, False))
        self.assertEqual(placement(args, 'eDP-1'), (0, 1080, True))

    def test_logical_layout_divides_by_scale(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(3840, 2160, current=True)])],
            [logical(0, 0, 1.6, ['eDP-1'], primary=True), logical(1600, 0, 2.0, ['DP-3'])],
        ))
        # laptop 1600x1000, external 1920x1080
        self.assertEqual(placement(args, 'eDP-1'), (160, 1080, True))
        self.assertIn('1.6', args)
        self.assertIn('2.0', args)

    def test_physical_layout_ignores_scale(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(3840, 2160, current=True)])],
            [logical(0, 0, 1.6, ['eDP-1'], primary=True), logical(2560, 0, 2.0, ['DP-3'])],
            layout_mode=PHYSICAL,
        ))
        self.assertEqual(placement(args, 'eDP-1'), (640, 2160, True))

    def test_rotated_external_uses_swapped_size(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(1920, 1080, current=True)])],
            [logical(0, 0, 1.0, ['eDP-1'], primary=True), logical(2560, 0, 1.0, ['DP-3'], transform=1)],
        ))
        # external is 1080x1920 after rotation
        self.assertEqual(placement(args, 'DP-3'), (740, 0, False))
        self.assertEqual(placement(args, 'eDP-1'), (0, 1920, True))
        self.assertIn('90', args)

    def test_mirrored_screens_are_split(self):
        args = screen_above.plan(state(
            [
                monitor('eDP-1', [mode(2560, 1600, preferred=True), mode(1920, 1080, current=True)], builtin=True),
                monitor('DP-4', [mode(1920, 1080, current=True, preferred=True)]),
            ],
            [logical(0, 0, 1.0, ['eDP-1', 'DP-4'], primary=True)],
        ))
        self.assertEqual(args.count('--logical-monitor'), 2)
        self.assertEqual(placement(args, 'DP-4'), (320, 0, False))
        self.assertEqual(placement(args, 'eDP-1'), (0, 1080, True))
        self.assertIn('2560x1600@60.000', args)

    def test_disabled_external_uses_preferred_mode_and_scale(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(3840, 2160, preferred=True, scale=2.0)])],
            [logical(0, 0, 1.0, ['eDP-1'], primary=True)],
        ))
        self.assertEqual(placement(args, 'DP-3'), (320, 0, False))
        self.assertEqual(placement(args, 'eDP-1'), (0, 1080, True))

    def test_keeps_external_primary(self):
        args = screen_above.plan(state(
            [LAPTOP, monitor('DP-3', [mode(1920, 1080, current=True)])],
            [logical(0, 0, 1.0, ['eDP-1']), logical(2560, 0, 1.0, ['DP-3'], primary=True)],
        ))
        self.assertTrue(placement(args, 'DP-3')[2])
        self.assertFalse(placement(args, 'eDP-1')[2])

    def test_refuses_without_exactly_one_external(self):
        with self.assertRaisesRegex(screen_above.LayoutError, 'one external'):
            screen_above.plan(state([LAPTOP], [logical(0, 0, 1.0, ['eDP-1'], primary=True)]))
        with self.assertRaisesRegex(screen_above.LayoutError, 'one external'):
            screen_above.plan(state(
                [
                    LAPTOP,
                    monitor('DP-3', [mode(1920, 1080, current=True)]),
                    monitor('DP-4', [mode(1920, 1080, current=True)]),
                ],
                [logical(0, 0, 1.0, ['eDP-1'], primary=True)],
            ))

    def test_refuses_without_laptop_screen(self):
        with self.assertRaisesRegex(screen_above.LayoutError, 'built-in'):
            screen_above.plan(state(
                [monitor('DP-3', [mode(1920, 1080, current=True)])],
                [logical(0, 0, 1.0, ['DP-3'], primary=True)],
            ))


if __name__ == '__main__':
    unittest.main()
