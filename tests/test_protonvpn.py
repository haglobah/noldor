import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONVERT = ROOT / 'modules/protonvpn/wg-to-nmconnection.sh'
TOGGLE = ROOT / 'home/modules/protonvpn-toggle.sh'
IPV6_BLOCK = ROOT / 'modules/protonvpn/ipv6-block.sh'

CONF = '''# Key for gondor
# Bouncing = 1
# NetShield = 1
[Interface]
PrivateKey = cHJpdmF0ZStrZXkvd2l0aD1zeW1ib2xzMTIzNDU2Nzg=
Address = 10.2.0.2/32, 2a07:b944::2:2/128
DNS = 10.2.0.1, 2a07:b944::2:1

[Peer]
# CH#42
PublicKey = cHVibGljK2tleS93aXRoPXN5bWJvbHMxMjM0NTY3ODk=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 185.159.157.1:51820
'''


def convert(text):
    return subprocess.run(
        ['bash', str(CONVERT)], input=text, capture_output=True, text=True
    )


def keyfile(text):
    """Parse the keyfile into {section: {key: value}}, keeping key order."""
    sections, current = {}, None
    for line in text.splitlines():
        if line.startswith('['):
            current = sections.setdefault(line.strip('[]'), {})
        elif '=' in line:
            key, value = line.split('=', 1)
            current[key] = value
    return sections


class ConvertTests(unittest.TestCase):
    def test_full_config_becomes_full_tunnel_profile(self):
        result = convert(CONF)
        self.assertEqual(result.returncode, 0, result.stderr)
        ini = keyfile(result.stdout)

        self.assertEqual(ini['connection']['type'], 'wireguard')
        self.assertEqual(ini['connection']['id'], 'ProtonVPN')
        self.assertEqual(ini['connection']['autoconnect'], 'false')
        self.assertEqual(
            ini['wireguard']['private-key'],
            'cHJpdmF0ZStrZXkvd2l0aD1zeW1ib2xzMTIzNDU2Nzg=',
        )
        peer = ini['wireguard-peer.cHVibGljK2tleS93aXRoPXN5bWJvbHMxMjM0NTY3ODk=']
        self.assertEqual(peer['endpoint'], '185.159.157.1:51820')
        self.assertEqual(peer['allowed-ips'], '0.0.0.0/0;::/0;')

        self.assertEqual(ini['ipv4']['method'], 'manual')
        self.assertEqual(ini['ipv4']['address1'], '10.2.0.2/32')
        self.assertEqual(ini['ipv4']['dns'], '10.2.0.1;')
        self.assertEqual(ini['ipv6']['method'], 'manual')
        self.assertEqual(ini['ipv6']['address1'], '2a07:b944::2:2/128')
        self.assertEqual(ini['ipv6']['dns'], '2a07:b944::2:1;')

    def test_persistent_keepalive_is_kept(self):
        ini = keyfile(convert(CONF + 'PersistentKeepalive = 25\n').stdout)
        peer = ini['wireguard-peer.cHVibGljK2tleS93aXRoPXN5bWJvbHMxMjM0NTY3ODk=']
        self.assertEqual(peer['persistent-keepalive'], '25')

    def test_all_dns_goes_through_the_tunnel(self):
        ini = keyfile(convert(CONF).stdout)
        # "~." makes the VPN link the default DNS route in resolved, and a
        # negative priority excludes the DNS servers of other links.
        self.assertEqual(ini['ipv4']['dns-search'], '~.;')
        self.assertTrue(int(ini['ipv4']['dns-priority']) < 0)

    def test_ipv4_only_config_disables_ipv6(self):
        conf = CONF.replace(', 2a07:b944::2:2/128', '').replace(', 2a07:b944::2:1', '')
        result = convert(conf)
        self.assertEqual(result.returncode, 0, result.stderr)
        ini = keyfile(result.stdout)
        self.assertEqual(ini['ipv6']['method'], 'disabled')
        self.assertNotIn('address1', ini['ipv6'])

    def test_crlf_line_endings_are_accepted(self):
        result = convert(CONF.replace('\n', '\r\n'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('\r', result.stdout)

    def test_missing_fields_fail_loudly(self):
        for line in ['PrivateKey', 'PublicKey', 'Endpoint', 'Address']:
            with self.subTest(missing=line):
                conf = '\n'.join(
                    l for l in CONF.splitlines() if not l.startswith(line)
                )
                result = convert(conf)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(line, result.stderr)
                self.assertEqual(result.stdout, '')


class ToggleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        self.calls = root / 'calls'
        (bin_dir / 'nmcli').write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$*" >> "$CALLS"\n'
            'case "$*" in\n'
            '  *"connection show --active"*) printf "%b" "$ACTIVE";;\n'
            '  *" up "*|*" down "*) exit "$SWITCH_STATUS";;\n'
            'esac\n'
        )
        (bin_dir / 'notify-send').write_text(
            '#!/bin/sh\nprintf "notify %s\\n" "$*" >> "$CALLS"\n'
        )
        for tool in bin_dir.iterdir():
            tool.chmod(0o755)
        self.env = {
            **os.environ,
            'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'CALLS': str(self.calls),
            'SWITCH_STATUS': '0',
        }

    def toggle(self, active, switch_status=0):
        env = {**self.env, 'ACTIVE': active, 'SWITCH_STATUS': str(switch_status)}
        result = subprocess.run(['bash', str(TOGGLE)], env=env, capture_output=True, text=True)
        return result, self.calls.read_text().splitlines()

    def test_inactive_profile_is_brought_up(self):
        result, calls = self.toggle('Mox\\ntailscale0\\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('connection up id ProtonVPN', calls)

    def test_active_profile_is_brought_down(self):
        result, calls = self.toggle('Mox\\nProtonVPN\\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('connection down id ProtonVPN', calls)

    def test_name_match_is_exact(self):
        # A Proton app connection like "ProtonVPN CH#42" is not ours.
        _, calls = self.toggle('ProtonVPN CH#42\\n')
        self.assertIn('connection up id ProtonVPN', calls)

    def test_failure_is_reported(self):
        result, calls = self.toggle('Mox\\n', switch_status=4)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(any(c.startswith('notify ') for c in calls), calls)


class Ipv6BlockTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        self.calls = root / 'calls'
        nft = bin_dir / 'nft'
        nft.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$*" >> "$CALLS"\n'
            '[ "$1" = -f ] && cat >> "$CALLS"\n'
            'exit "$NFT_STATUS"\n'
        )
        nft.chmod(0o755)
        self.env = {
            **os.environ,
            'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'CALLS': str(self.calls),
            'NFT_STATUS': '0',
        }

    def dispatch(self, connection, action, nft_status=0):
        env = {**self.env, 'CONNECTION_ID': connection, 'NFT_STATUS': str(nft_status)}
        result = subprocess.run(
            ['bash', str(IPV6_BLOCK), 'proton0', action],
            env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL,
        )
        calls = self.calls.read_text() if self.calls.exists() else ''
        return result, calls

    def test_up_installs_a_table_that_rejects_ipv6_outside_the_tunnel(self):
        result, calls = self.dispatch('ProtonVPN', 'up')
        self.assertEqual(result.returncode, 0, result.stderr)
        # One atomic nft run: stale table replaced, rules in a single batch.
        rules = calls
        self.assertIn('table ip6 protonvpn-ipv6-block', rules)
        self.assertIn('hook output', rules)
        self.assertIn('hook forward', rules)
        self.assertIn('oifname "lo" accept', rules)
        self.assertIn('oifname "proton0" accept', rules)
        self.assertIn('reject', rules)

    def test_down_removes_the_table(self):
        result, calls = self.dispatch('ProtonVPN', 'down')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('destroy table ip6 protonvpn-ipv6-block', calls)

    def test_other_connections_are_ignored(self):
        for action in ['up', 'down']:
            with self.subTest(action=action):
                _, calls = self.dispatch('Mox', action)
                self.assertEqual(calls, '')

    def test_other_actions_are_ignored(self):
        _, calls = self.dispatch('ProtonVPN', 'dhcp4-change')
        self.assertEqual(calls, '')

    def test_nft_failure_is_reported(self):
        result, _ = self.dispatch('ProtonVPN', 'up', nft_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('IPv6', result.stderr)


if __name__ == '__main__':
    unittest.main()
