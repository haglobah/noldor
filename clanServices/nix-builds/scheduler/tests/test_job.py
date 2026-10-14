import unittest

from nix_builds.job import BuilderGone, BuildJobs, NoBuildJobs, run_job
from nix_builds.webhook import Push

JOB = Push("haglobah/ht", "refs/heads/main", "c" * 40, "main")


class FakeOps:
    """Records calls; each step can be told to fail or to return data."""

    def __init__(self, jobs=None, cached=(), after_build=None, fail=None):
        self.jobs = (
            jobs
            if jobs is not None
            else BuildJobs(
                drvs=["/nix/store/d1.drv", "/nix/store/d2.drv"],
                outputs=["/nix/store/o1", "/nix/store/o2"],
            )
        )
        self.cached = set(cached)
        # What the cache holds once aule built and pushed.
        outputs = getattr(self.jobs, "outputs", [])
        self.after_build = set(after_build if after_build is not None else outputs)
        self.fail = fail or set()
        self.calls = []
        self.statuses = []

    def _step(self, name, *args):
        self.calls.append(name)
        if name in self.fail:
            raise RuntimeError(f"{name} broke")

    def status(self, push, state, description):
        self.statuses.append((state, description))

    def eval_jobs(self, push):
        self._step("eval", push)
        if isinstance(self.jobs, Exception):
            raise self.jobs
        return self.jobs

    def missing(self, paths):
        self._step("missing", paths)
        return [p for p in paths if p not in self.cached]

    def ensure_builder(self):
        self._step("ensure_builder")
        return "aule-at-1.2.3.4"

    def build(self, builder, drvs):
        self._step("build", builder, drvs)
        self.cached |= self.after_build

    def wait_cached(self, paths, timeout):
        self._step("wait_cached", paths)
        return [p for p in paths if p not in self.cached]


class RunJob(unittest.TestCase):
    def test_everything_cached_does_not_wake_the_builder(self):
        ops = FakeOps(cached=["/nix/store/o1", "/nix/store/o2"])
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "success")
        self.assertNotIn("ensure_builder", ops.calls)
        self.assertEqual(ops.statuses[-1][0], "success")

    def test_missing_paths_are_built_on_the_builder(self):
        ops = FakeOps(cached=["/nix/store/o1"])
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "success")
        self.assertEqual(
            ops.calls, ["eval", "missing", "ensure_builder", "build", "wait_cached"]
        )
        self.assertEqual(ops.statuses[0][0], "pending")
        self.assertEqual(ops.statuses[-1][0], "success")

    def test_a_build_that_never_reaches_the_cache_fails(self):
        ops = FakeOps(after_build=["/nix/store/o1"])
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "failure")
        self.assertIn("/nix/store/o2", result.detail)
        self.assertEqual(ops.statuses[-1][0], "failure")

    def test_a_failed_build_fails_the_job(self):
        ops = FakeOps(fail={"build"})
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "failure")
        self.assertIn("build broke", result.detail)
        self.assertNotIn("wait_cached", ops.calls)

    def test_a_failed_eval_fails_the_job_without_waking_the_builder(self):
        ops = FakeOps(fail={"eval"})
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "failure")
        self.assertNotIn("ensure_builder", ops.calls)

    def test_a_repo_without_build_jobs_is_skipped(self):
        ops = FakeOps(jobs=NoBuildJobs("no buildJobs.x86_64-linux"))
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "skipped")
        self.assertNotIn("ensure_builder", ops.calls)
        # No commit status: the repo did not ask for builds.
        self.assertEqual(ops.statuses, [])

    def test_a_builder_that_cannot_start_is_an_error_not_a_failure(self):
        # Hetzner sold out or the API is down: retry later, do not blame the commit.
        ops = FakeOps(fail={"ensure_builder"})
        result = run_job(JOB, ops)
        self.assertEqual(result.state, "error")
        self.assertEqual(ops.statuses[-1][0], "error")

    def test_a_builder_that_vanished_mid_build_is_an_error(self):
        ops = FakeOps()

        def gone(builder, drvs):
            raise BuilderGone("aule was deleted during the build")

        ops.build = gone
        self.assertEqual(run_job(JOB, ops).state, "error")

    def test_a_status_api_outage_does_not_fail_the_build(self):
        ops = FakeOps(cached=["/nix/store/o1", "/nix/store/o2"])

        def broken_status(*args):
            raise RuntimeError("GitHub is down")

        ops.status = broken_status
        self.assertEqual(run_job(JOB, ops).state, "success")


if __name__ == "__main__":
    unittest.main()
