import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/test-backup-restore.sh'

class RestoreCommandTests(unittest.TestCase):
    def run_command(self, status=0, args=()):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('clan', 'borg', 'nix'):
                blocked = root / name
                blocked.write_text('#!/bin/sh\necho Unexpected direct backup access >&2\nexit 99\n')
                blocked.chmod(0o755)
            systemctl = root / 'systemctl'
            systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$CALLS"\nexit "$STATUS"\n')
            systemctl.chmod(0o755)
            env = dict(os.environ, PATH=tmp + ':' + os.environ['PATH'], CALLS=str(root / 'calls'), STATUS=str(status))
            result = subprocess.run(['bash', str(SCRIPT), *args], env=env, capture_output=True, text=True)
            calls = (root / 'calls').read_text() if (root / 'calls').exists() else ''
            return result, calls

    def test_runs_configured_rehearsal(self):
        result, calls = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, 'start\ntodo-home-backup-test.service\n')

    def test_preserves_service_failure(self):
        result, _ = self.run_command(status=7)
        self.assertEqual(result.returncode, 7)

    def test_rejects_arguments_without_starting_service(self):
        result, calls = self.run_command(args=('unexpected',))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')

if __name__ == '__main__':
    unittest.main()
