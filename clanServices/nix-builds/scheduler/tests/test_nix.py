import json
import unittest

from nix_builds.job import BuildJobs, NoBuildJobs
from nix_builds.nix import Nix, NixFailed
from nix_builds.webhook import Push

PUSH = Push("haglobah/ht", "refs/heads/main", "c" * 40, "main")


class FakeRun:
    """Stands in for subprocess.run: answers by the nix subcommand."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def __call__(self, argv, env, input=None):
        self.calls.append((argv, env))
        key = argv[1]
        answer = self.answers[key]
        if callable(answer):
            answer = answer(argv)
        return answer  # (returncode, stdout, stderr)


def nix(run):
    return Nix(
        run=run,
        system="x86_64-linux",
        cache_store="s3://nix-cache?profile=nix-cache-read",
        cache_credentials="/run/creds",
        ssh_key="/run/key",
        known_hosts="/etc/aule_known_hosts",
        ssh_user="nix-ssh",
        sleep=lambda s: None,
    )


class EvalJobs(unittest.TestCase):
    def test_collects_every_output_of_every_job(self):
        jobs = {
            "backend": {"drv": "/nix/store/b.drv", "outs": ["/nix/store/b"]},
            "frontend": {
                "drv": "/nix/store/f.drv",
                "outs": ["/nix/store/f", "/nix/store/f-doc"],
            },
        }
        run = FakeRun({"eval": (0, json.dumps(jobs), "")})
        result = nix(run).eval_jobs(PUSH, token="ghs_x")
        self.assertEqual(
            result,
            BuildJobs(
                drvs=["/nix/store/b.drv", "/nix/store/f.drv"],
                outputs=["/nix/store/b", "/nix/store/f", "/nix/store/f-doc"],
            ),
        )
        argv, env = run.calls[0]
        # The commit is pinned; the token reaches nix through NIX_CONFIG, not argv.
        self.assertIn(
            'builtins.getFlake "github:haglobah/ht/' + "c" * 40 + '"', argv[-1]
        )
        self.assertNotIn("ghs_x", " ".join(argv))
        self.assertIn("access-tokens = github.com=ghs_x", env["NIX_CONFIG"])

    def test_no_build_jobs(self):
        run = FakeRun({"eval": (0, "null", "")})
        with self.assertRaises(NoBuildJobs):
            nix(run).eval_jobs(PUSH, token="t")

    def test_eval_error_carries_the_end_of_stderr(self):
        run = FakeRun({"eval": (1, "", "lots\nof\nerror: attribute 'x' missing\n")})
        with self.assertRaises(NixFailed) as e:
            nix(run).eval_jobs(PUSH, token="t")
        self.assertIn("attribute 'x' missing", str(e.exception))


class Cache(unittest.TestCase):
    def test_missing_asks_the_cache_per_path_without_negative_caching(self):
        run = FakeRun(
            {"path-info": lambda argv: (0 if argv[-1] == "/nix/store/a" else 1, "", "")}
        )
        self.assertEqual(
            nix(run).missing(["/nix/store/a", "/nix/store/b"]), ["/nix/store/b"]
        )
        argv, env = run.calls[0]
        self.assertIn("s3://nix-cache?profile=nix-cache-read", argv)
        self.assertIn("narinfo-cache-negative-ttl", argv)
        self.assertEqual(env["AWS_SHARED_CREDENTIALS_FILE"], "/run/creds")

    def test_wait_cached_polls_until_present(self):
        seen = {"n": 0}

        def path_info(argv):
            seen["n"] += 1
            return (0 if seen["n"] > 2 else 1, "", "")

        run = FakeRun({"path-info": path_info})
        self.assertEqual(nix(run).wait_cached(["/nix/store/a"], timeout=60), [])

    def test_wait_cached_gives_up_after_the_timeout(self):
        run = FakeRun({"path-info": (1, "", "")})
        n = nix(run)
        n.clock = iter(range(0, 10_000, 30)).__next__
        self.assertEqual(n.wait_cached(["/nix/store/a"], timeout=60), ["/nix/store/a"])


class Build(unittest.TestCase):
    def test_copies_derivations_then_builds_them_remotely(self):
        run = FakeRun({"copy": (0, "", ""), "build": (0, "", "")})
        nix(run).build("1.2.3.4", ["/nix/store/b.drv"])
        (copy, env), (build, _) = run.calls
        self.assertEqual(copy[:4], ["nix", "copy", "--derivation", "--to"])
        self.assertEqual(copy[4], "ssh-ng://nix-ssh@1.2.3.4")
        self.assertIn("--store", build)
        self.assertIn("/nix/store/b.drv^*", build)
        # Host key pinned under the alias; never trust a new key silently.
        self.assertIn("StrictHostKeyChecking=yes", env["NIX_SSHOPTS"])
        self.assertIn("HostKeyAlias=aule", env["NIX_SSHOPTS"])

    def test_a_failed_build_raises(self):
        run = FakeRun(
            {"copy": (0, "", ""), "build": (1, "", "error: builder failed\n")}
        )
        with self.assertRaises(NixFailed):
            nix(run).build("1.2.3.4", ["/nix/store/b.drv"])


if __name__ == "__main__":
    unittest.main()
