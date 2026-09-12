"""Run: python3 -m unittest discover -s home/programs/kitty."""
import json
from pathlib import Path
import os
import subprocess
import tempfile
import unittest


class FishWorkspaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module = Path(__file__).resolve().parents[1] / 'fish.nix'
        expression = f'''let c = (import {module} {{config={{}}; lib={{}}; pkgs={{}};}}).config.programs.fish;
          in {{ body = c.functions.w.body or ""; who = c.shellAliases.who or ""; }}'''
        cls.config = json.loads(subprocess.check_output(
            ['nix-instantiate', '--eval', '--strict', '--json', '--expr', expression], text=True))

    def run_command(self, arguments, kitty_status=0):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            directory = root / 'project space;$(literal)'
            directory.mkdir()
            history_directory = root / 'history' / 'known project'
            history_directory.mkdir(parents=True)
            log = root / 'arguments.json'
            for name in ('kitty', 'w'):
                executable = root / name
                executable.write_text(
                    '#!/usr/bin/env python3\nimport json, os, sys\n'
                    'from pathlib import Path\n'
                    'Path(os.environ["WORKSPACE_TEST_LOG"]).write_text(json.dumps(sys.argv[1:]))\n'
                    'sys.exit(int(os.environ["WORKSPACE_TEST_STATUS"]))\n')
                executable.chmod(0o755)
            script = root / 'run.fish'
            script.write_text('function w\n' + self.config['body'] + '\nend\n'
                              'function who\n' + self.config['who'] + ' $argv\nend\n'
                              '$argv\n')
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ['PATH'],
                       WORKSPACE_TEST_LOG=str(log), WORKSPACE_TEST_STATUS=str(kitty_status),
                       _ZO_DATA_DIR=str(root / 'zoxide'))
            subprocess.run(['zoxide', 'add', str(history_directory)], env=env, check=True)
            result = subprocess.run(['fish', '--no-config', str(script), *arguments],
                                    cwd=tmp, env=env, text=True, capture_output=True)
            return result, json.loads(log.read_text()) if log.exists() else None, root

    def test_relative_directory_is_absolute_and_one_argument(self):
        result, args, root = self.run_command(['w', 'project space;$(literal)'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ['@', '--to=unix:@mykitty', 'kitten', 'balance_splits.py',
                                'workspace', str(root / 'project space;$(literal)')])

    def test_no_argument_uses_current_directory(self):
        result, args, root = self.run_command(['w'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(args)
        self.assertEqual(args[-1], str(root))

    def test_invalid_directory_does_not_launch(self):
        result, args, _ = self.run_command(['w', 'missing'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(args)

    def test_keyword_resolves_from_history(self):
        result, args, root = self.run_command(['w', 'known'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args[-1], str(root / 'history' / 'known project'))

    def test_multiple_keywords_resolve_from_history(self):
        result, args, root = self.run_command(['w', 'history', 'known'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args[-1], str(root / 'history' / 'known project'))

    def test_kitty_failure_is_propagated(self):
        result, _, _ = self.run_command(['w', '.'], kitty_status=7)
        self.assertEqual(result.returncode, 7)

    def test_who_calls_system_w_with_arguments(self):
        result, args, _ = self.run_command(['who', '-h'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ['-h'])
