import base64
import json
import os
import subprocess
import tempfile
import unittest

from nix_builds.github import GitHub, app_jwt


def b64decode(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


class AppJwt(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.TemporaryDirectory()
        cls.key = os.path.join(cls.dir.name, "app.pem")
        cls.pub = os.path.join(cls.dir.name, "app.pub")
        subprocess.run(
            [
                "openssl",
                "genpkey",
                "-algorithm",
                "RSA",
                "-pkeyopt",
                "rsa_keygen_bits:2048",
                "-out",
                cls.key,
            ],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", cls.key, "-pubout", "-out", cls.pub],
            check=True,
            capture_output=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.dir.cleanup()

    def test_claims_and_header(self):
        token = app_jwt("12345", self.key, now=1_000_000)
        header, claims, _ = token.split(".")
        self.assertEqual(json.loads(b64decode(header)), {"alg": "RS256", "typ": "JWT"})
        # iat backdated for clock drift, exp within GitHub's 10-minute limit.
        self.assertEqual(
            json.loads(b64decode(claims)),
            {"iat": 1_000_000 - 60, "exp": 1_000_000 + 540, "iss": "12345"},
        )

    def test_signature_verifies_with_the_public_key(self):
        token = app_jwt("12345", self.key, now=1_000_000)
        signing_input, signature = token.rsplit(".", 1)
        with tempfile.NamedTemporaryFile() as sig:
            sig.write(b64decode(signature))
            sig.flush()
            ok = subprocess.run(
                [
                    "openssl",
                    "dgst",
                    "-sha256",
                    "-verify",
                    self.pub,
                    "-signature",
                    sig.name,
                ],
                input=signing_input.encode(),
                capture_output=True,
                check=False,
            )
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)


class FakeApi:
    def __init__(self):
        self.calls = []

    def __call__(self, method, path, token, body=None):
        self.calls.append((method, path, token, body))
        if path == "/app/installations":
            return [{"id": 7}]
        if path == "/app/installations/7/access_tokens":
            return {"token": "ghs_inst", "expires_at": "2099-01-01T00:00:00Z"}
        if path == "/installation/repositories?per_page=100&page=1":
            return {
                "repositories": [{"full_name": "haglobah/ht", "default_branch": "main"}]
            }
        if path == "/installation/repositories?per_page=100&page=2":
            return {"repositories": []}
        if path.startswith("/repos/haglobah/ht/git/matching-refs/"):
            if path.endswith("/heads/main"):
                return [
                    {
                        "ref": "refs/heads/main",
                        "object": {"type": "commit", "sha": "m" * 40},
                    }
                ]
            return [
                {"ref": "refs/tags/v1", "object": {"type": "tag", "sha": "t" * 40}},
                {"ref": "refs/tags/v2", "object": {"type": "commit", "sha": "c" * 40}},
            ]
        if path == "/repos/haglobah/ht/git/tags/" + "t" * 40:
            return {"object": {"type": "commit", "sha": "p" * 40}}
        if path.startswith("/repos/haglobah/ht/statuses/"):
            return {}
        raise AssertionError(f"unexpected {method} {path}")


class GitHubClient(unittest.TestCase):
    def setUp(self):
        self.api = FakeApi()
        self.gh = GitHub(self.api, jwt=lambda: "jwt")

    def test_repos_of_every_installation(self):
        self.assertEqual(self.gh.repos(), {"haglobah/ht": "main"})
        self.assertIn(
            ("POST", "/app/installations/7/access_tokens", "jwt", None), self.api.calls
        )

    def test_refs_peel_annotated_tags_to_commits(self):
        self.gh.repos()
        self.assertEqual(
            self.gh.refs("haglobah/ht", "main"),
            {
                "refs/heads/main": "m" * 40,
                "refs/tags/v1": "p" * 40,
                "refs/tags/v2": "c" * 40,
            },
        )

    def test_installation_token_is_reused_until_it_expires(self):
        self.gh.repos()
        self.gh.token("haglobah/ht")
        self.gh.token("haglobah/ht")
        minted = [c for c in self.api.calls if c[1].endswith("/access_tokens")]
        self.assertEqual(len(minted), 1)

    def test_status_is_truncated_to_githubs_limit(self):
        self.gh.repos()
        self.gh.status(
            "haglobah/ht", "s" * 40, "failure", "x" * 500, "https://builds.example/"
        )
        method, path, token, body = self.api.calls[-1]
        self.assertEqual(
            (method, path, token),
            ("POST", "/repos/haglobah/ht/statuses/" + "s" * 40, "ghs_inst"),
        )
        self.assertEqual(body["context"], "nix-builds")
        self.assertEqual(body["state"], "failure")
        self.assertLessEqual(len(body["description"]), 140)


if __name__ == "__main__":
    unittest.main()
