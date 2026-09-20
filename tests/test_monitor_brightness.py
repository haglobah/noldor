import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'home/pkgs/monitor-brightness/monitor-brightness.sh'


def display(number, bus, vendor, valid=True):
    heading = f'Display {number}' if valid else 'Invalid display'
    return f'{heading}\n   I2C bus: /dev/i2c-{bus}\n   Monitor: {vendor}:Model:Serial\n'


class MonitorBrightnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.connector = self.root / 'sys/class/drm/card1-DP-3'
        self.connector.mkdir(parents=True)
        (self.connector / 'status').write_text('connected\n')
        (self.connector / 'edid').write_bytes(b'LG display')
        (self.connector / 'ddc').symlink_to('../../../devices/i2c-8')
        mocks = {
            'asdbctl': '#!/bin/sh\nexit "$APPLE_STATUS"\n',
            'ddcutil': '''#!/bin/sh
if [ "$1" = detect ]; then
    echo detect >> "$DETECT_CALLS"
    printf '%s' "$DETECTION"
    if [ "$CHANGE_DURING_DETECT" = 1 ]; then
        printf disconnected > "$MONITOR_BRIGHTNESS_SYSFS_ROOT/class/drm/card1-DP-3/status"
    fi
    exit "$DETECT_STATUS"
fi
printf '%s\\n' "$*" >> "$CALLS"
[ "$2" != "$FAILED_BUS" ]
''',
            'notify-send': '#!/bin/sh\nexit 0\n',
        }
        for name, content in mocks.items():
            executable = self.root / name
            executable.write_text(content)
            executable.chmod(0o755)

    def run_helper(self, detection='', direction='up', apple_status=1, failed_bus='',
                   detect_status=0, change_during_detect=False):
        calls = self.root / 'calls'
        calls.unlink(missing_ok=True)
        env = dict(os.environ, PATH=str(self.root) + ':' + os.environ['PATH'],
                   XDG_RUNTIME_DIR=str(self.root), CALLS=str(calls),
                   MONITOR_BRIGHTNESS_SYSFS_ROOT=str(self.root / 'sys'),
                   DETECT_CALLS=str(self.root / 'detect-calls'),
                   DETECT_STATUS=str(detect_status), DETECTION=detection,
                   CHANGE_DURING_DETECT=str(int(change_during_detect)),
                   APPLE_STATUS=str(apple_status), FAILED_BUS=str(failed_bus))
        result = subprocess.run(['bash', '-euo', 'pipefail', str(SCRIPT), direction],
                                env=env, capture_output=True, text=True)
        return result, calls.read_text().splitlines() if calls.exists() else []

    def detection_count(self):
        return len((self.root / 'detect-calls').read_text().splitlines())

    def test_adjusts_all_brands_and_skips_invalid_displays(self):
        detection = (display(1, 8, 'GSM') + display(0, 5, 'BOE', valid=False)
                     + display(2, 12, 'DEL') + display(3, 14, 'SAM'))
        result, calls = self.run_helper(detection)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [f'--bus {bus} setvcp 10 + 10' for bus in (8, 12, 14)])

    def test_redetects_bus_and_can_decrease(self):
        for bus in (8, 19):
            (self.connector / 'ddc').unlink()
            (self.connector / 'ddc').symlink_to(f'../../../devices/i2c-{bus}')
            result, calls = self.run_helper(display(1, bus, 'GSM'), direction='down')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, [f'--bus {bus} setvcp 10 - 10'])

    def test_apple_success_does_not_skip_ddc_monitors(self):
        result, calls = self.run_helper(display(1, 8, 'GSM'), apple_status=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['--bus 8 setvcp 10 + 10'])

    def test_apple_only_still_succeeds(self):
        result, calls = self.run_helper(apple_status=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])

    def test_failure_is_visible_and_other_monitors_are_attempted(self):
        result, calls = self.run_helper(display(1, 8, 'GSM') + display(2, 12, 'DEL'),
                                        failed_bus=8)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Could not adjust', result.stderr)
        self.assertEqual(calls, ['--bus 8 setvcp 10 + 10', '--bus 12 setvcp 10 + 10'])

    def test_no_supported_monitors_fails(self):
        result, calls = self.run_helper(display(0, 5, 'BOE', valid=False))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_invalid_direction_fails_without_ddc_writes(self):
        result, calls = self.run_helper(display(1, 8, 'GSM'), direction='sideways')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])

    def test_unchanged_connection_uses_cache(self):
        self.run_helper(display(1, 8, 'GSM'))
        result, calls = self.run_helper('unexpected discovery', direction='down')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.detection_count(), 1)
        self.assertEqual(calls, ['--bus 8 setvcp 10 - 10'])

    def test_replacement_monitor_invalidates_cache(self):
        self.run_helper(display(1, 8, 'GSM'))
        (self.connector / 'edid').write_bytes(b'different monitor')
        result, calls = self.run_helper(display(1, 19, 'SAM'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.detection_count(), 2)
        self.assertEqual(calls, ['--bus 19 setvcp 10 + 10'])

    def test_disconnection_does_not_write_to_old_bus(self):
        self.run_helper(display(1, 8, 'GSM'))
        (self.connector / 'status').write_text('disconnected\n')
        result, calls = self.run_helper('')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.detection_count(), 2)
        self.assertEqual(calls, [])

    def test_failed_write_refreshes_cache_without_replaying_change(self):
        self.run_helper(display(1, 8, 'GSM'))
        result, calls = self.run_helper(display(1, 19, 'GSM'), failed_bus=8)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, ['--bus 8 setvcp 10 + 10'])
        self.assertEqual(self.detection_count(), 2)
        result, calls = self.run_helper('not used')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['--bus 19 setvcp 10 + 10'])
        self.assertEqual(self.detection_count(), 2)

    def test_failed_detection_is_not_cached(self):
        result, calls = self.run_helper(display(1, 8, 'GSM'), detect_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        result, calls = self.run_helper(display(1, 19, 'GSM'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.detection_count(), 2)
        self.assertEqual(calls, ['--bus 19 setvcp 10 + 10'])

    def test_connection_change_during_discovery_prevents_writes(self):
        result, calls = self.run_helper(display(1, 8, 'GSM'), change_during_detect=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assertIn('connections changed', result.stderr)
        self.assertFalse((self.root / 'monitor-brightness/displays').exists())

    def test_adapter_change_invalidates_cache_without_edid_change(self):
        adapters = self.root / 'sys/class/i2c-dev'
        adapters.mkdir(parents=True)
        (adapters / 'i2c-8').symlink_to('../../devices/old-adapter')
        self.run_helper(display(1, 8, 'GSM'))
        (adapters / 'i2c-8').unlink()
        (adapters / 'i2c-19').symlink_to('../../devices/new-adapter')
        result, calls = self.run_helper(display(1, 19, 'GSM'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.detection_count(), 2)
        self.assertEqual(calls, ['--bus 19 setvcp 10 + 10'])


if __name__ == '__main__':
    unittest.main()
