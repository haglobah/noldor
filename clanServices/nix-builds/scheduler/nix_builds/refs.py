"""Which refs of a repo get built: the default branch and release tags."""

import fnmatch
import re

TAG_PREFIX = "refs/tags/"


def wants_ref(ref: str, default_branch: str, tag_pattern: str) -> bool:
    if ref == f"refs/heads/{default_branch}":
        return True
    return ref.startswith(TAG_PREFIX) and fnmatch.fnmatchcase(
        ref.removeprefix(TAG_PREFIX), tag_pattern
    )


def wanted_refs(refs: dict, default_branch: str, tag_pattern: str) -> dict:
    """From a poll's {ref: sha}: the branch head and the newest matching tag.

    Webhooks build every new tag. A poll only catches up on the newest one,
    so a first poll does not start the builder for years of old releases.
    """
    wanted = {
        r: s for r, s in refs.items() if wants_ref(r, default_branch, tag_pattern)
    }
    tags = [r for r in wanted if r.startswith(TAG_PREFIX)]
    newest = max(tags, key=_version_key, default=None)
    return {
        r: s for r, s in wanted.items() if not r.startswith(TAG_PREFIX) or r == newest
    }


def _version_key(ref: str):
    # v1.10 sorts after v1.9: compare digit runs as numbers.
    parts = re.split(r"(\d+)", ref.removeprefix(TAG_PREFIX))
    return [(0, int(p)) if p.isdigit() else (1, p) for p in parts]
