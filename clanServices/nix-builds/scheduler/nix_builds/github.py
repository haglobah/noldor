"""GitHub App: installation tokens, installed repos, refs, commit statuses.

Installing the App on a repo registers it. Installation tokens live an hour;
they are minted from a JWT signed with the App's private key. Python's
stdlib cannot sign RS256, so openssl does.
"""

import base64
import json
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime

API = "https://api.github.com"
CONTEXT = "nix-builds"


class GitHubError(Exception):
    pass


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def app_jwt(app_id: str, key_file: str, now=None) -> str:
    now = int(time.time() if now is None else now)
    # Backdated a minute for clock drift; GitHub allows at most 10 minutes.
    header = _b64(
        json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode()
    )
    claims = _b64(
        json.dumps(
            {"iat": now - 60, "exp": now + 540, "iss": str(app_id)},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{claims}"
    sig = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_file],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout
    return f"{signing_input}.{_b64(sig)}"


def http_api(method: str, path: str, token: str, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "nix-builds",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
    except urllib.error.HTTPError as e:
        raise GitHubError(
            f"{method} {path}: HTTP {e.code} {e.read()[:300]!r}"
        ) from None
    except OSError as e:
        raise GitHubError(f"{method} {path}: {e}") from None
    return json.loads(data) if data else {}


class GitHub:
    def __init__(self, api=http_api, jwt=None, clock=time.time):
        self.api = api
        self.jwt = jwt
        self.clock = clock
        self.installation_of = {}  # repo -> installation id
        self.tokens = {}  # installation id -> (token, expires at)

    def _installation_token(self, installation: int) -> str:
        cached = self.tokens.get(installation)
        if cached and cached[1] - 300 > self.clock():
            return cached[0]
        got = self.api(
            "POST", f"/app/installations/{installation}/access_tokens", self.jwt()
        )
        expires = datetime.fromisoformat(
            got["expires_at"].replace("Z", "+00:00")
        ).timestamp()
        self.tokens[installation] = (got["token"], expires)
        return got["token"]

    def repos(self) -> dict:
        """{owner/name: default branch} over every installation of the App."""
        found, owners = {}, {}
        for inst in self.api("GET", "/app/installations", self.jwt()):
            token = self._installation_token(inst["id"])
            page = 1
            while True:
                got = self.api(
                    "GET", f"/installation/repositories?per_page=100&page={page}", token
                )
                repos = got.get("repositories", [])
                if not repos:
                    break
                for r in repos:
                    found[r["full_name"]] = r["default_branch"]
                    owners[r["full_name"]] = inst["id"]
                page += 1
        self.installation_of = owners
        return found

    def token(self, repo: str) -> str:
        if repo not in self.installation_of:
            self.repos()
        if repo not in self.installation_of:
            raise GitHubError(f"the App is not installed on {repo}")
        return self._installation_token(self.installation_of[repo])

    def refs(self, repo: str, default_branch: str) -> dict:
        """{ref: commit sha} for the default branch and all tags."""
        token = self.token(repo)
        out = {}
        for prefix in (f"heads/{default_branch}", "tags/"):
            for r in self.api(
                "GET", f"/repos/{repo}/git/matching-refs/{prefix}", token
            ):
                obj = r["object"]
                if (
                    r["ref"].startswith("refs/heads/")
                    and r["ref"] != f"refs/heads/{default_branch}"
                ):
                    continue  # matching-refs is a prefix match: main-old, main2
                # Annotated tags point at a tag object; nix needs the commit.
                while obj["type"] == "tag":
                    obj = self.api(
                        "GET", f"/repos/{repo}/git/tags/{obj['sha']}", token
                    )["object"]
                if obj["type"] == "commit":
                    out[r["ref"]] = obj["sha"]
        return out

    def status(
        self, repo: str, sha: str, state: str, description: str, target_url=None
    ):
        body = {"state": state, "context": CONTEXT, "description": description[:140]}
        if target_url:
            body["target_url"] = target_url
        self.api("POST", f"/repos/{repo}/statuses/{sha}", self.token(repo), body)
