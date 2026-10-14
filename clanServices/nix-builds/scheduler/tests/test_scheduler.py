import os
import tempfile
import unittest

from nix_builds.job import Result
from nix_builds.scheduler import Scheduler
from nix_builds.state import State
from nix_builds.webhook import Push, RepoChange


class FakeGitHub:
    def __init__(self):
        self.installed = {"haglobah/ht": "main"}
        self.heads = {
            "haglobah/ht": {"refs/heads/main": "m" * 40, "refs/tags/v1": "t" * 40}
        }
        self.fail = False

    def repos(self):
        if self.fail:
            raise RuntimeError("GitHub is down")
        return dict(self.installed)

    def refs(self, repo, default_branch):
        return dict(self.heads[repo])


class SchedulerTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.state = State(os.path.join(self.dir.name, "s.sqlite"))
        self.github = FakeGitHub()
        self.ran = []
        self.results = {}
        self.notes = []

        def run(push):
            self.ran.append(push)
            return self.results.get(push.sha, Result("success", "ok"))

        self.s = Scheduler(
            github=self.github,
            state=self.state,
            run=run,
            notify=lambda title, text, priority: self.notes.append(
                (title, text, priority)
            ),
            tag_pattern="v*",
        )

    def tearDown(self):
        self.state.close()
        self.dir.cleanup()

    def drain(self):
        while self.s.step():
            pass

    def test_poll_queues_the_heads_of_installed_repos(self):
        self.s.poll()
        self.drain()
        self.assertEqual(sorted(p.sha for p in self.ran), ["m" * 40, "t" * 40])

    def test_a_built_head_is_not_built_again_on_the_next_poll(self):
        self.s.poll()
        self.drain()
        self.s.poll()
        self.drain()
        self.assertEqual(len(self.ran), 2)

    def test_webhook_push_for_a_wanted_ref(self):
        self.s.poll()
        self.drain()
        self.ran.clear()
        self.s.handle([Push("haglobah/ht", "refs/heads/main", "n" * 40, "main")])
        self.drain()
        self.assertEqual([p.sha for p in self.ran], ["n" * 40])

    def test_webhook_pushes_for_other_refs_or_repos_are_ignored(self):
        self.s.poll()
        self.drain()
        self.ran.clear()
        self.s.handle(
            [
                Push("haglobah/ht", "refs/heads/feature", "f" * 40, "main"),
                Push("someone/else", "refs/heads/main", "e" * 40, "main"),
            ]
        )
        self.drain()
        self.assertEqual(self.ran, [])

    def test_installing_the_app_on_a_repo_polls_it(self):
        self.s.poll()
        self.drain()
        self.ran.clear()
        self.github.installed["haglobah/notable"] = "main"
        self.github.heads["haglobah/notable"] = {"refs/heads/main": "b" * 40}
        self.s.handle([RepoChange(added=["haglobah/notable"])])
        self.drain()
        self.assertEqual([p.repo for p in self.ran], ["haglobah/notable"])

    def test_a_failure_notifies(self):
        self.results["m" * 40] = Result("failure", "build failed: x")
        self.s.poll()
        self.drain()
        self.assertEqual(len(self.notes), 1)
        title, text, _ = self.notes[0]
        self.assertIn("haglobah/ht", title)
        self.assertIn("build failed: x", text)

    def test_an_error_notifies_once_per_commit_while_it_retries(self):
        self.results["m" * 40] = Result("error", "builder did not start: sold out")
        for _ in range(3):
            self.s.poll()
            self.drain()
        errors = [n for n in self.notes if "sold out" in n[1]]
        self.assertEqual(len(errors), 1)
        # Retried on every poll: an error records no result.
        self.assertEqual(sum(p.sha == "m" * 40 for p in self.ran), 3)

    def test_a_github_outage_during_poll_is_logged_not_raised(self):
        self.github.fail = True
        with self.assertLogs("nix_builds.scheduler", level="WARNING"):
            self.s.poll()


if __name__ == "__main__":
    unittest.main()
