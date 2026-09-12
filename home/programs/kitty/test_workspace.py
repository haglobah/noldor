"""Run with python3 -m unittest discover -s home/programs/kitty."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

from balance_splits import handle_result


class WorkspaceTests(unittest.TestCase):
    def run_workspace(self, directory=None):
        root = SimpleNamespace(horizontal=True, one=1,
                               two=SimpleNamespace(horizontal=True, one=2, two=3, bias=.5),
                               bias=.5)
        tab = SimpleNamespace(current_layout=SimpleNamespace(pairs_root=root), relayout=Mock())
        source = object()
        boss = SimpleNamespace(
            active_tab=SimpleNamespace(relayout=Mock()),
            window_id_map={7: source, 42: SimpleNamespace(tabref=lambda: tab)},
            call_remote_control=Mock(side_effect=['42', None, '43', '44']))
        args = ['balance_splits.py', 'workspace']
        if directory is not None:
            args.append(directory)
        handle_result(args, None, 7, boss)
        calls = [call.args for call in boss.call_remote_control.call_args_list]
        self.assertEqual(len(calls), 4)
        expected_cwd = '--cwd=' + (directory or 'current')
        self.assertIn('--type=tab', calls[0][1])
        for index in (0, 2, 3):
            self.assertIs(calls[index][0], source)
            self.assertIn(expected_cwd, calls[index][1])
            self.assertIn('--source-window=id:7', calls[index][1])
        self.assertEqual(calls[1][1], ('goto-layout', '--match=window_id:42', 'splits'))
        for index in (2, 3):
            self.assertIn('--match=window_id:42', calls[index][1])
            self.assertIn('--location=vsplit', calls[index][1])
        self.assertAlmostEqual(root.bias, 1 / 3)
        self.assertEqual(root.two.bias, .5)
        tab.relayout.assert_called_once()
        boss.active_tab.relayout.assert_not_called()

    def test_current_directory(self):
        self.run_workspace()

    def test_explicit_directory_with_shell_characters(self):
        self.run_workspace('/tmp/project space;$(literal)')


if __name__ == '__main__':
    unittest.main()
