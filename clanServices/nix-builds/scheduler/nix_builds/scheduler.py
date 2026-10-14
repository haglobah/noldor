"""Turns webhook events and polls into queued jobs, and runs them one by one."""

import logging

from .job import Result
from .refs import wanted_refs, wants_ref
from .webhook import Push, RepoChange

log = logging.getLogger(__name__)


class Scheduler:
    def __init__(self, github, state, run, notify, tag_pattern="v*"):
        self.github = github
        self.state = state
        self.run = run  # Push -> job.Result
        self.notify = notify  # (title, text, priority) -> None
        self.tag_pattern = tag_pattern
        self.repos = {}  # owner/name -> default branch, from the last poll
        self.alerted_errors = set()  # (repo, sha): one alert while it retries

    def poll(self):
        """Queue the branch head and newest release tag of every installed repo."""
        try:
            self.repos = self.github.repos()
        except Exception as e:
            log.warning("poll: listing the App's repos failed: %s", e)
            return
        for repo, branch in self.repos.items():
            try:
                refs = self.github.refs(repo, branch)
            except Exception as e:
                log.warning("poll: refs of %s failed: %s", repo, e)
                continue
            for ref, sha in wanted_refs(refs, branch, self.tag_pattern).items():
                if self.state.enqueue(Push(repo, ref, sha, branch)):
                    log.info("queued %s %s %s (poll)", repo, ref, sha[:12])

    def handle(self, events):
        for event in events:
            if isinstance(event, RepoChange):
                log.info("App repos changed: +%s -%s", event.added, event.removed)
                self.poll()
            elif isinstance(event, Push):
                if event.repo not in self.repos:
                    log.info(
                        "ignoring push to %s: the App is not installed there",
                        event.repo,
                    )
                elif not wants_ref(event.ref, event.default_branch, self.tag_pattern):
                    log.debug("ignoring push to %s %s", event.repo, event.ref)
                elif self.state.enqueue(event):
                    log.info(
                        "queued %s %s %s (webhook)",
                        event.repo,
                        event.ref,
                        event.sha[:12],
                    )

    def step(self) -> bool:
        """Run one queued job. False when the queue is empty."""
        push = self.state.take()
        if push is None:
            return False
        try:
            result = self.run(push)
        except Exception as e:  # a bug, not a build result: keep going
            log.exception("job %s %s crashed", push.repo, push.sha[:12])
            result = Result("error", f"scheduler crashed: {e}")
        self.state.finish(push, result.state, result.detail)
        self._alert(push, result)
        return True

    def _alert(self, push, result):
        key = (push.repo, push.sha)
        title = (
            f"nix-builds: {push.repo} {push.ref.removeprefix('refs/')} {push.sha[:12]}"
        )
        if result.state == "failure":
            self.notify(f"{title} failed", result.detail, 4)
        elif result.state == "error" and key not in self.alerted_errors:
            self.alerted_errors.add(key)
            self.notify(
                f"{title}: not built yet", result.detail + " (retrying every poll)", 3
            )
        elif result.state == "success":
            self.alerted_errors.discard(key)
