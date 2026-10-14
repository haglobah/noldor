import unittest

from nix_builds.refs import wanted_refs, wants_ref

TAGS = "v*"


class WantsRef(unittest.TestCase):
    def test_default_branch_and_matching_tags(self):
        self.assertTrue(wants_ref("refs/heads/main", "main", TAGS))
        self.assertTrue(wants_ref("refs/tags/v1.2", "main", TAGS))

    def test_other_branches_and_tags_are_skipped(self):
        self.assertFalse(wants_ref("refs/heads/feature", "main", TAGS))
        self.assertFalse(wants_ref("refs/tags/nightly", "main", TAGS))
        self.assertFalse(wants_ref("refs/pull/1/head", "main", TAGS))


class WantedRefs(unittest.TestCase):
    def test_poll_takes_the_branch_head_and_only_the_newest_tag(self):
        # Polling must not wake the builder for every old release tag.
        refs = {
            "refs/heads/main": "m",
            "refs/heads/feature": "f",
            "refs/tags/v1.9": "a",
            "refs/tags/v1.10": "b",
            "refs/tags/nightly": "n",
        }
        self.assertEqual(
            wanted_refs(refs, "main", TAGS),
            {"refs/heads/main": "m", "refs/tags/v1.10": "b"},
        )

    def test_no_tags(self):
        self.assertEqual(
            wanted_refs({"refs/heads/main": "m"}, "main", TAGS),
            {"refs/heads/main": "m"},
        )


if __name__ == "__main__":
    unittest.main()
