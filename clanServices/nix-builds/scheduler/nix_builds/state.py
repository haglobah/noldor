"""The job queue and build results, in SQLite.

One queued job per (repo, ref): a newer commit replaces an older one that
has not started. A commit with a result (success, failure, skipped) is not
queued again; `nix-builds retry` deletes the result. A job that was running
when the scheduler stopped is queued again on the next start.
"""

import sqlite3
import time

from .webhook import Push

SCHEMA = """
create table if not exists jobs (
  repo text not null,
  ref text not null,
  sha text not null,
  default_branch text not null,
  running integer not null default 0,
  queued_at real not null,
  primary key (repo, ref, running)
);
create table if not exists results (
  repo text not null,
  sha text not null,
  state text not null,
  detail text not null,
  finished_at real not null,
  primary key (repo, sha)
);
"""


class State:
    def __init__(self, path: str):
        self.db = sqlite3.connect(path)
        self.db.executescript(SCHEMA)
        with self.db:
            # Requeue interrupted jobs, unless a newer commit already waits.
            self.db.execute(
                "delete from jobs where running = 1 and exists (select 1 from jobs q"
                " where q.repo = jobs.repo and q.ref = jobs.ref and q.running = 0)"
            )
            self.db.execute("update jobs set running = 0")

    def close(self):
        self.db.close()

    def enqueue(self, push: Push) -> bool:
        """Queue a commit unless it has a result or is running. True if queued.

        A ref has at most one running and one queued job: a newer commit
        replaces the queued one and waits for the running one.
        """
        if self.result(push.repo, push.sha) is not None:
            return False
        with self.db:
            running = self.db.execute(
                "select 1 from jobs where repo = ? and ref = ? and sha = ? and running = 1",
                (push.repo, push.ref, push.sha),
            ).fetchone()
            if running:
                return False
            self.db.execute(
                "insert or replace into jobs values (?, ?, ?, ?, 0, ?)",
                (push.repo, push.ref, push.sha, push.default_branch, time.time()),
            )
        return True

    def take(self):
        """The oldest queued job whose ref is not running, marked running."""
        with self.db:
            row = self.db.execute(
                "select repo, ref, sha, default_branch from jobs q where running = 0"
                " and not exists (select 1 from jobs r where r.repo = q.repo"
                " and r.ref = q.ref and r.running = 1)"
                " order by queued_at limit 1"
            ).fetchone()
            if row is None:
                return None
            self.db.execute(
                "update jobs set running = 1 where repo = ? and ref = ? and running = 0",
                row[:2],
            )
        return Push(*row)

    def finish(self, push: Push, state: str, detail: str):
        """Record a result. "error" (builder or API trouble) is not recorded,
        so the next poll queues the commit again."""
        with self.db:
            self.db.execute(
                "delete from jobs where repo = ? and ref = ? and running = 1",
                (push.repo, push.ref),
            )
            if state != "error":
                self.db.execute(
                    "insert or replace into results values (?, ?, ?, ?, ?)",
                    (push.repo, push.sha, state, detail, time.time()),
                )

    def result(self, repo: str, sha: str):
        row = self.db.execute(
            "select state, detail from results where repo = ? and sha = ?", (repo, sha)
        ).fetchone()
        return tuple(row) if row else None

    def forget(self, repo: str, sha: str) -> bool:
        with self.db:
            cur = self.db.execute(
                "delete from results where repo = ? and sha = ?", (repo, sha)
            )
        return cur.rowcount > 0

    def recent(self, limit: int = 20) -> list:
        return self.db.execute(
            "select repo, sha, state, detail, finished_at from results"
            " order by finished_at desc limit ?",
            (limit,),
        ).fetchall()

    def queued(self) -> list:
        return self.db.execute(
            "select repo, ref, sha, running from jobs order by queued_at"
        ).fetchall()
