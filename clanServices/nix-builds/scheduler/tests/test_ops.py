import unittest

from nix_builds.job import BuilderGone
from nix_builds.nix import NixFailed
from nix_builds.ops import BuilderTimeout, Ops
from nix_builds.webhook import Push

PUSH = Push("haglobah/ht", "refs/heads/main", "c" * 40, "main")


class FakeHetzner:
    def __init__(self, exists_after_build=True):
        self.exists_after_build = exists_after_build

    def ensure(self):
        return "1.2.3.4"

    def exists(self):
        return self.exists_after_build


class FakeNix:
    def __init__(self, ping_after=0, build_error=None):
        self.pings = 0
        self.ping_after = ping_after
        self.build_error = build_error

    def ping(self, ip):
        self.pings += 1
        return self.pings > self.ping_after

    def build(self, ip, drvs):
        if self.build_error:
            raise self.build_error


class FakeGitHub:
    def __init__(self):
        self.statuses = []

    def token(self, repo):
        return "ghs"

    def status(self, repo, sha, state, description, target_url=None):
        self.statuses.append((repo, sha, state, description, target_url))


def ops(nix=None, hetzner=None, github=None):
    clock = iter(range(0, 100_000, 10)).__next__
    return Ops(
        github=github or FakeGitHub(),
        hetzner=hetzner or FakeHetzner(),
        nix=nix or FakeNix(),
        status_url="https://builds.hagenlocher.me",
        boot_timeout=60,
        sleep=lambda s: None,
        clock=clock,
    )


class EnsureBuilder(unittest.TestCase):
    def test_waits_until_aule_answers(self):
        nix = FakeNix(ping_after=3)
        self.assertEqual(ops(nix=nix).ensure_builder(), "1.2.3.4")
        self.assertEqual(nix.pings, 4)

    def test_gives_up_after_the_boot_timeout(self):
        with self.assertRaises(BuilderTimeout):
            ops(nix=FakeNix(ping_after=10_000)).ensure_builder()


class Build(unittest.TestCase):
    def test_a_failure_with_aule_still_there_is_the_builds_fault(self):
        o = ops(nix=FakeNix(build_error=NixFailed("builder for x failed")))
        with self.assertRaises(NixFailed):
            o.build("1.2.3.4", ["/nix/store/x.drv"])

    def test_a_failure_after_aule_vanished_is_builder_gone(self):
        o = ops(
            nix=FakeNix(build_error=NixFailed("connection closed")),
            hetzner=FakeHetzner(exists_after_build=False),
        )
        with self.assertRaises(BuilderGone):
            o.build("1.2.3.4", ["/nix/store/x.drv"])


class Status(unittest.TestCase):
    def test_states_map_to_github_and_link_to_the_status_page(self):
        gh = FakeGitHub()
        ops(github=gh).status(PUSH, "pending", "building 2 missing outputs")
        self.assertEqual(
            gh.statuses,
            [
                (
                    "haglobah/ht",
                    "c" * 40,
                    "pending",
                    "building 2 missing outputs",
                    "https://builds.hagenlocher.me",
                )
            ],
        )


if __name__ == "__main__":
    unittest.main()
