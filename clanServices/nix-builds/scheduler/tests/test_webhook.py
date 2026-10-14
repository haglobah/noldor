import hashlib
import hmac
import unittest

from nix_builds.webhook import Push, RepoChange, parse_event, verify_signature

SECRET = b"s3cret"


def sign(body: bytes) -> str:
    return "sha256=" + hmac.new(SECRET, body, hashlib.sha256).hexdigest()


class VerifySignature(unittest.TestCase):
    def test_accepts_a_valid_signature(self):
        body = b'{"zen":"hi"}'
        self.assertTrue(verify_signature(SECRET, body, sign(body)))

    def test_rejects_a_tampered_body(self):
        self.assertFalse(verify_signature(SECRET, b"{}", sign(b'{"a":1}')))

    def test_rejects_a_missing_or_malformed_header(self):
        for header in (None, "", "sha1=abc", "sha256=", "sha256=zz"):
            with self.subTest(header=header):
                self.assertFalse(verify_signature(SECRET, b"{}", header))

    def test_rejects_everything_without_a_secret(self):
        body = b"{}"
        self.assertFalse(verify_signature(b"", body, sign(body)))


class ParseEvent(unittest.TestCase):
    def payload(self, ref, after="a" * 40, head=None, deleted=False):
        return {
            "ref": ref,
            "after": after,
            "deleted": deleted,
            "head_commit": {"id": head or after},
            "repository": {"full_name": "haglobah/ht", "default_branch": "main"},
        }

    def test_branch_push(self):
        self.assertEqual(
            parse_event("push", self.payload("refs/heads/main")),
            [Push("haglobah/ht", "refs/heads/main", "a" * 40, "main")],
        )

    def test_tag_push_uses_the_commit_not_the_tag_object(self):
        # An annotated tag's `after` is the tag object; nix needs the commit.
        event = self.payload("refs/tags/v1", after="t" * 40, head="c" * 40)
        self.assertEqual(
            parse_event("push", event),
            [Push("haglobah/ht", "refs/tags/v1", "c" * 40, "main")],
        )

    def test_deleted_ref_is_ignored(self):
        event = self.payload("refs/heads/main", after="0" * 40, deleted=True)
        self.assertEqual(parse_event("push", event), [])

    def test_push_without_head_commit_is_ignored(self):
        event = self.payload("refs/heads/main")
        event["head_commit"] = None
        self.assertEqual(parse_event("push", event), [])

    def test_installation_repositories(self):
        event = {
            "action": "added",
            "repositories_added": [{"full_name": "haglobah/notable"}],
            "repositories_removed": [{"full_name": "haglobah/old"}],
        }
        self.assertEqual(
            parse_event("installation_repositories", event),
            [RepoChange(added=["haglobah/notable"], removed=["haglobah/old"])],
        )

    def test_other_events_are_ignored(self):
        self.assertEqual(parse_event("ping", {"zen": "hi"}), [])
        self.assertEqual(parse_event("issues", {}), [])


if __name__ == "__main__":
    unittest.main()
