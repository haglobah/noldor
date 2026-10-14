"""One job: make sure a commit's buildJobs outputs are in the cache.

The steps talk to the outside world through `ops` (see ops.py), so the
flow here is tested with fakes. Results:

- success: every output is in the cache.
- skipped: the commit has no buildJobs for this system. No commit status.
- failure: evaluation or the build failed, or outputs never reached the
  cache. The commit gets a red status and is not retried automatically.
- error: the builder could not be started or vanished mid-build. Not the
  commit's fault: no result is recorded, so the next poll retries it.
"""

import logging
from dataclasses import dataclass

log = logging.getLogger(__name__)

# How long aule's push queue may take to upload a build's outputs.
PUSH_TIMEOUT = 15 * 60


@dataclass(frozen=True)
class BuildJobs:
    drvs: list
    outputs: list


@dataclass(frozen=True)
class NoBuildJobs(Exception):
    reason: str


class BuilderGone(Exception):
    """The builder disappeared during the build (deleted, crashed)."""


@dataclass(frozen=True)
class Result:
    state: str
    detail: str


def run_job(push, ops) -> Result:
    short = push.sha[:12]
    try:
        jobs = ops.eval_jobs(push)
    except NoBuildJobs as e:
        log.info("%s %s: skipped, %s", push.repo, short, e.reason)
        return Result("skipped", e.reason)
    except Exception as e:
        return _finish(push, ops, Result("failure", f"evaluation failed: {e}"))

    _status(push, ops, "pending", f"checking {len(jobs.outputs)} outputs")
    try:
        missing = ops.missing(jobs.outputs)
    except Exception as e:
        return _finish(push, ops, Result("error", f"cache lookup failed: {e}"))
    if not missing:
        return _finish(
            push, ops, Result("success", f"all {len(jobs.outputs)} outputs cached")
        )

    _status(push, ops, "pending", f"building {len(missing)} missing outputs")
    try:
        builder = ops.ensure_builder()
    except Exception as e:
        return _finish(push, ops, Result("error", f"builder did not start: {e}"))
    try:
        ops.build(builder, jobs.drvs)
    except BuilderGone as e:
        return _finish(push, ops, Result("error", f"builder lost: {e}"))
    except Exception as e:
        return _finish(push, ops, Result("failure", f"build failed: {e}"))

    still = ops.wait_cached(missing, PUSH_TIMEOUT)
    if still:
        return _finish(
            push,
            ops,
            Result("failure", "built, but not in the cache: " + " ".join(still)),
        )
    return _finish(push, ops, Result("success", f"built {len(missing)} outputs"))


def _finish(push, ops, result: Result) -> Result:
    log.log(
        logging.INFO if result.state == "success" else logging.WARNING,
        "%s %s %s: %s %s",
        push.repo,
        push.ref,
        push.sha[:12],
        result.state,
        result.detail,
    )
    _status(push, ops, result.state, result.detail)
    return result


def _status(push, ops, state, description):
    # A GitHub outage must not fail or block the build itself.
    try:
        ops.status(push, state, description)
    except Exception as e:
        log.warning(
            "commit status for %s %s not posted: %s", push.repo, push.sha[:12], e
        )
