"""The job steps (see job.py) wired to GitHub, Hetzner and nix."""

import logging
import time

from .job import BuilderGone

log = logging.getLogger(__name__)


class BuilderTimeout(Exception):
    pass


class Ops:
    def __init__(
        self,
        github,
        hetzner,
        nix,
        status_url=None,
        boot_timeout=600,
        sleep=time.sleep,
        clock=time.monotonic,
    ):
        self.github = github
        self.hetzner = hetzner
        self.nix = nix
        # No public status page by default: it would list private repo names.
        self.status_url = status_url
        self.boot_timeout = boot_timeout
        self.sleep = sleep
        self.clock = clock

    def status(self, push, state, description):
        self.github.status(push.repo, push.sha, state, description, self.status_url)

    def eval_jobs(self, push):
        return self.nix.eval_jobs(push, token=self.github.token(push.repo))

    def missing(self, paths):
        return self.nix.missing(paths)

    def wait_cached(self, paths, timeout):
        return self.nix.wait_cached(paths, timeout)

    def ensure_builder(self) -> str:
        ip = self.hetzner.ensure()
        start = self.clock()
        # A fresh server boots in about a minute; nix-daemon answers last.
        # Until sshd listens, a ping waits out ssh's ConnectTimeout (5 s),
        # so a short sleep keeps the gap between tries small.
        while not self.nix.ping(ip):
            if self.clock() - start >= self.boot_timeout:
                raise BuilderTimeout(
                    f"aule at {ip} did not answer within {self.boot_timeout}s; it still bills until its reaper deletes it"
                )
            self.sleep(2)
        log.info("builder aule is up at %s", ip)
        return ip

    def build(self, ip, drvs):
        try:
            self.nix.build(ip, drvs)
        except Exception as e:
            # A dropped connection looks like a failed build. If the server
            # is gone (reaper cap, manual delete), it is not the commit's fault.
            if not self.hetzner.exists():
                raise BuilderGone(f"aule vanished during the build: {e}") from e
            raise
