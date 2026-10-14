"""The nix commands: evaluate buildJobs, ask the cache, build on aule."""

import collections
import json
import os
import subprocess
import sys
import time

from .job import BuildJobs, NoBuildJobs

FEATURES = "experimental-features = nix-command flakes\n"

# Evaluates a pinned commit's buildJobs.<system> to drv and output paths,
# or null when the flake has none. Flat attribute sets only, like a
# hydraJobs set without nesting.
EVAL = """
let
  flake = builtins.getFlake "github:{repo}/{sha}";
  system = "{system}";
in
if flake ? buildJobs && flake.buildJobs ? ${{system}} then
  builtins.mapAttrs (name: drv: {{
    drv = drv.drvPath;
    outs = map (o: drv.${{o}}.outPath) (drv.outputs or [ "out" ]);
  }}) flake.buildJobs.${{system}}
else
  null
"""


class NixFailed(Exception):
    pass


def run(argv, env, input=None):
    """Runs nix, streams stderr to the journal, keeps its tail for errors."""
    proc = subprocess.Popen(
        argv,
        env={**os.environ, **env},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    tail = collections.deque(maxlen=40)
    for line in proc.stderr:
        sys.stderr.write(line)
        tail.append(line)
    out = proc.stdout.read()
    return proc.wait(), out, "".join(tail)


class Nix:
    def __init__(
        self,
        system,
        cache_store,
        cache_credentials,
        ssh_key,
        known_hosts,
        ssh_user="nix-ssh",
        run=run,
        sleep=time.sleep,
        clock=time.monotonic,
    ):
        self.run = run
        self.system = system
        self.cache_store = cache_store
        self.cache_credentials = cache_credentials
        self.ssh_key = ssh_key
        self.known_hosts = known_hosts
        self.ssh_user = ssh_user
        self.sleep = sleep
        self.clock = clock

    def _nix(self, argv, env=None):
        rc, out, err = self.run(["nix", *argv], {"NIX_CONFIG": FEATURES, **(env or {})})
        if rc != 0:
            last = err.strip().splitlines()[-3:]
            raise NixFailed(f"nix {argv[0]} exited {rc}: " + " | ".join(last))
        return out

    def eval_jobs(self, push, token: str) -> BuildJobs:
        expr = EVAL.format(repo=push.repo, sha=push.sha, system=self.system)
        # The token is a nix setting, so it never shows up in argv (ps).
        env = {"NIX_CONFIG": FEATURES + f"access-tokens = github.com={token}\n"}
        rc, out, err = self.run(
            ["nix", "eval", "--json", "--impure", "--expr", expr], env
        )
        if rc != 0:
            last = err.strip().splitlines()[-3:]
            raise NixFailed(f"nix eval exited {rc}: " + " | ".join(last))
        jobs = json.loads(out)
        if jobs is None:
            raise NoBuildJobs(f"no buildJobs.{self.system} in the flake")
        names = sorted(jobs)
        return BuildJobs(
            drvs=[jobs[n]["drv"] for n in names],
            outputs=[o for n in names for o in jobs[n]["outs"]],
        )

    def _cached(self, path: str) -> bool:
        # A zero negative TTL: a path pushed a minute ago must count.
        rc, _, _ = self.run(
            [
                "nix",
                "path-info",
                "--store",
                self.cache_store,
                "--option",
                "narinfo-cache-negative-ttl",
                "0",
                path,
            ],
            {
                "NIX_CONFIG": FEATURES,
                "AWS_SHARED_CREDENTIALS_FILE": self.cache_credentials,
            },
        )
        return rc == 0

    def missing(self, paths: list) -> list:
        return [p for p in paths if not self._cached(p)]

    def wait_cached(self, paths: list, timeout: float) -> list:
        """Waits for aule's push queue; returns what is still missing."""
        start = self.clock()
        remaining = list(paths)
        while True:
            remaining = self.missing(remaining)
            if not remaining or self.clock() - start >= timeout:
                return remaining
            self.sleep(15)

    def build(self, ip: str, drvs: list):
        """Copies the derivations to aule and builds them there.

        aule fetches sources and dependencies itself; outputs stay on aule,
        whose post-build hook signs and pushes them to the cache.
        """
        store = f"ssh-ng://{self.ssh_user}@{ip}"
        env = self._ssh_env()
        self._nix(["copy", "--derivation", "--to", store, *drvs], env)
        self._nix(
            ["build", "--store", store, "--no-link", "-L", *[f"{d}^*" for d in drvs]],
            env,
        )

    def ping(self, ip: str) -> bool:
        try:
            self._nix(
                ["store", "info", "--store", f"ssh-ng://{self.ssh_user}@{ip}"],
                self._ssh_env(),
            )
            return True
        except NixFailed:
            return False

    def _ssh_env(self):
        # The host key is pinned under the alias `aule`: every server made
        # from the snapshot has the same key, but a new IP. Keepalives
        # notice a server that vanished mid-build within a minute.
        return {
            "NIX_SSHOPTS": " ".join(
                [
                    f"-i {self.ssh_key}",
                    "-o HostKeyAlias=aule",
                    f"-o UserKnownHostsFile={self.known_hosts}",
                    "-o StrictHostKeyChecking=yes",
                    "-o ConnectTimeout=10",
                    "-o ServerAliveInterval=15",
                    "-o ServerAliveCountMax=4",
                ]
            )
        }
