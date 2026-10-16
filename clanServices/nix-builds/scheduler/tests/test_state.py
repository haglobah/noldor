import os
import tempfile
import unittest

from nix_builds.state import State
from nix_builds.webhook import Push


def push(sha, ref="refs/heads/main", repo="haglobah/ht"):
    return Push(repo, ref, sha, "main")


class StateTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.state = State(os.path.join(self.dir.name, "state.sqlite"))

    def tearDown(self):
        self.state.close()
        self.dir.cleanup()

    def test_queue_is_first_in_first_out(self):
        self.state.enqueue(push("a"))
        self.state.enqueue(push("b", ref="refs/tags/v1"))
        self.assertEqual(self.state.take().sha, "a")
        self.assertEqual(self.state.take().sha, "b")
        self.assertIsNone(self.state.take())

    def test_a_newer_commit_replaces_the_queued_one_on_the_same_ref(self):
        self.state.enqueue(push("a"))
        self.state.enqueue(push("b"))
        self.assertEqual(self.state.take().sha, "b")
        self.assertIsNone(self.state.take())

    def test_a_commit_pushed_while_its_ref_builds_waits_for_it(self):
        self.state.enqueue(push("a"))
        running = self.state.take()
        self.assertFalse(self.state.enqueue(push("a")))  # already running
        self.assertTrue(self.state.enqueue(push("b")))
        self.assertIsNone(self.state.take())  # same ref still running
        self.state.finish(running, "success", "")
        self.assertEqual(self.state.take().sha, "b")

    def test_restart_keeps_the_newer_commit_over_the_interrupted_one(self):
        self.state.enqueue(push("a"))
        self.state.take()
        self.state.enqueue(push("b"))
        self.state.close()
        self.state = State(os.path.join(self.dir.name, "state.sqlite"))
        self.state.requeue_interrupted()
        self.assertEqual(self.state.take().sha, "b")
        self.assertIsNone(self.state.take())

    def test_an_error_leaves_the_commit_free_to_queue_again(self):
        self.state.enqueue(push("a"))
        self.state.finish(self.state.take(), "error", "Hetzner is down")
        self.assertTrue(self.state.enqueue(push("a")))

    def test_a_built_commit_is_not_queued_again(self):
        self.state.enqueue(push("a"))
        job = self.state.take()
        self.state.finish(job, "success", "built 3 paths")
        self.assertFalse(self.state.enqueue(push("a")))
        self.assertIsNone(self.state.take())

    def test_a_failed_commit_is_not_retried_by_polling(self):
        # A broken commit would otherwise wake aule every five minutes.
        self.state.enqueue(push("a"))
        self.state.finish(self.state.take(), "failure", "build failed")
        self.assertFalse(self.state.enqueue(push("a")))

    def test_an_interrupted_job_runs_again_after_a_restart(self):
        self.state.enqueue(push("a"))
        self.state.take()
        self.state.close()
        self.state = State(os.path.join(self.dir.name, "state.sqlite"))
        self.state.requeue_interrupted()
        self.assertEqual(self.state.take().sha, "a")

    def test_reading_the_state_leaves_a_running_job_alone(self):
        # `nix-builds status` opens the database while the daemon builds.
        self.state.enqueue(push("a"))
        job = self.state.take()
        State(os.path.join(self.dir.name, "state.sqlite")).close()
        self.state.finish(job, "success", "built 1 outputs")
        self.assertIsNone(self.state.take())

    def test_last_result(self):
        self.state.enqueue(push("a"))
        self.state.finish(self.state.take(), "failure", "eval failed")
        self.assertEqual(
            self.state.result("haglobah/ht", "a"), ("failure", "eval failed")
        )
        self.assertIsNone(self.state.result("haglobah/ht", "zzz"))


if __name__ == "__main__":
    unittest.main()
