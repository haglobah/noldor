"""GitHub webhook checks and the events the scheduler acts on."""

import hashlib
import hmac
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Push:
    """A commit on a ref of a repo, from a webhook or a poll."""

    repo: str  # owner/name
    ref: str  # refs/heads/main, refs/tags/v1
    sha: str  # the commit, never a tag object
    default_branch: str


@dataclass(frozen=True)
class RepoChange:
    """The App was installed on or removed from repos."""

    added: list = field(default_factory=list)
    removed: list = field(default_factory=list)


def verify_signature(secret: bytes, body: bytes, header) -> bool:
    """X-Hub-Signature-256 is HMAC-SHA256 of the raw body, hex, prefixed."""
    if not secret or not header or not header.startswith("sha256="):
        return False
    expected = hmac.new(secret, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header.removeprefix("sha256="))


def parse_event(name: str, payload: dict) -> list:
    if name == "push":
        return _push(payload)
    if name == "installation_repositories":
        return [
            RepoChange(
                added=[r["full_name"] for r in payload.get("repositories_added", [])],
                removed=[
                    r["full_name"] for r in payload.get("repositories_removed", [])
                ],
            )
        ]
    return []


def _push(payload: dict) -> list:
    head = payload.get("head_commit")
    if payload.get("deleted") or not head:
        return []
    repo = payload["repository"]
    # For an annotated tag, `after` is the tag object; head_commit is the commit.
    return [Push(repo["full_name"], payload["ref"], head["id"], repo["default_branch"])]
