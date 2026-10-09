"""Place the one external screen above the laptop screen, centered.

Reads the layout from Mutter's DisplayConfig D-Bus API and applies the new
one with `gdctl set --persistent`, so GNOME stores it in monitors.xml like a
change made in Settings.
"""

import subprocess
import sys

LAYOUT_PHYSICAL = 2
# Mutter transform ids, in gdctl's spelling. Odd ids rotate by 90 or 270.
TRANSFORMS = ['normal', '90', '180', '270', 'flipped', 'flipped-90', 'flipped-180', 'flipped-270']


class LayoutError(Exception):
    pass


def _screen(monitor, logical_monitors, layout_mode):
    (connector, *_), modes, props = monitor
    owner = next((lm for lm in logical_monitors if connector in [spec[0] for spec in lm[5]]), None)
    current = next((m for m in modes if m[6].get('is-current')), None)
    preferred = next((m for m in modes if m[6].get('is-preferred')), modes[0])
    if owner is not None and len(owner[5]) == 1 and current is not None:
        mode, scale, transform, primary = current, owner[2], owner[3], owner[4]
    else:
        # Disabled or mirrored: a shared mirror mode is rarely what the
        # screen should run on its own.
        mode, scale = preferred, preferred[4]
        transform = 0
        primary = owner is not None and owner[4]
    width, height = mode[1], mode[2]
    if transform % 2:
        width, height = height, width
    if layout_mode != LAYOUT_PHYSICAL:
        width, height = round(width / scale), round(height / scale)
    return {
        'connector': connector,
        'builtin': props.get('is-builtin', False),
        'mode': mode[0],
        'scale': scale,
        'transform': transform,
        'primary': primary,
        'width': width,
        'height': height,
    }


def _logical_monitor_args(screen, x, y):
    args = ['--logical-monitor']
    if screen['primary']:
        args.append('--primary')
    args += [
        '--scale', str(screen['scale']),
        '--transform', TRANSFORMS[screen['transform']],
        '--x', str(x),
        '--y', str(y),
        '--monitor', screen['connector'],
        '--mode', screen['mode'],
    ]
    return args


def plan(state):
    """Return gdctl arguments for the layout, given an unpacked GetCurrentState."""
    _serial, monitors, logical_monitors, props = state
    layout_mode = props.get('layout-mode', 1)
    screens = [_screen(m, logical_monitors, layout_mode) for m in monitors]
    laptops = [s for s in screens if s['builtin']]
    externals = [s for s in screens if not s['builtin']]
    if len(laptops) != 1:
        raise LayoutError('no built-in screen found')
    if len(externals) != 1:
        raise LayoutError(f'need exactly one external screen, found {len(externals)}')
    laptop, external = laptops[0], externals[0]
    if not laptop['primary'] and not external['primary']:
        laptop['primary'] = True
    if laptop['primary'] and external['primary']:
        external['primary'] = False
    width = max(laptop['width'], external['width'])
    return (
        ['set', '--persistent']
        + _logical_monitor_args(external, (width - external['width']) // 2, 0)
        + _logical_monitor_args(laptop, (width - laptop['width']) // 2, external['height'])
    )


def current_state():
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    reply = bus.call_sync(
        'org.gnome.Mutter.DisplayConfig',
        '/org/gnome/Mutter/DisplayConfig',
        'org.gnome.Mutter.DisplayConfig',
        'GetCurrentState',
        None,
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    return reply.unpack()


def notify(message):
    print(message, file=sys.stderr)
    subprocess.run(['notify-send', '--app-name=screen-above', 'Screen layout', message], check=False)


def main():
    dry_run = '--dry-run' in sys.argv[1:]
    try:
        args = plan(current_state())
    except LayoutError as error:
        notify(str(error))
        return 1
    if dry_run:
        print(' '.join(['gdctl'] + args))
        return 0
    result = subprocess.run(['gdctl'] + args, capture_output=True, text=True)
    if result.returncode != 0:
        notify(f'gdctl failed: {result.stderr.strip()}')
        return result.returncode
    return 0


if __name__ == '__main__':
    sys.exit(main())
