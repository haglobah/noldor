import unittest

from nix_builds.hetzner import ApiError, Hetzner, NoCapacity, NoSnapshot

SERVER = {
    "id": 9,
    "name": "aule",
    "status": "running",
    "public_net": {"ipv4": {"ip": "1.2.3.4"}},
}


class FakeApi:
    def __init__(self, servers=(), snapshots=(5,), refuse=()):
        self.servers = list(servers)
        self.snapshots = list(snapshots)
        self.refuse = set(refuse)  # (type, location) pairs Hetzner turns down
        self.created = []

    def __call__(self, method, path, body=None):
        if method == "GET" and path.startswith("/servers?label_selector="):
            return {"servers": self.servers}
        if method == "GET" and path.startswith("/images?type=snapshot"):
            return {
                "images": [
                    {"id": i, "created": f"2026-10-0{i}T00:00:00Z"}
                    for i in self.snapshots
                ]
            }
        if method == "POST" and path == "/servers":
            key = (body["server_type"], body["location"])
            if key in self.refuse:
                raise ApiError(412, "resource_unavailable")
            self.created.append(body)
            server = dict(SERVER, public_net={"ipv4": {"ip": "5.6.7.8"}})
            self.servers = [server]
            return {"server": server}
        if method == "GET" and path == "/servers/9":
            if not self.servers:
                raise ApiError(404, "not_found")
            return {"server": self.servers[0]}
        raise AssertionError(f"unexpected {method} {path}")


def hetzner(api):
    return Hetzner(
        api, name="aule", types=["cx53", "ccx33"], locations=["fsn1", "nbg1"]
    )


class Ensure(unittest.TestCase):
    def test_a_running_server_is_reused(self):
        api = FakeApi(servers=[SERVER])
        self.assertEqual(hetzner(api).ensure(), "1.2.3.4")
        self.assertEqual(api.created, [])

    def test_creates_from_the_newest_snapshot_with_the_label(self):
        api = FakeApi(snapshots=[3, 5, 4])
        self.assertEqual(hetzner(api).ensure(), "5.6.7.8")
        body = api.created[0]
        self.assertEqual(body["image"], "5")
        self.assertEqual((body["server_type"], body["location"]), ("cx53", "fsn1"))
        self.assertEqual(body["labels"], {"machine": "aule"})
        self.assertEqual(body["name"], "aule")

    def test_falls_back_through_locations_then_types(self):
        api = FakeApi(refuse={("cx53", "fsn1"), ("cx53", "nbg1")})
        hetzner(api).ensure()
        self.assertEqual(
            (api.created[0]["server_type"], api.created[0]["location"]),
            ("ccx33", "fsn1"),
        )

    def test_nothing_available(self):
        refuse = {(t, l) for t in ("cx53", "ccx33") for l in ("fsn1", "nbg1")}
        with self.assertRaises(NoCapacity):
            hetzner(FakeApi(refuse=refuse)).ensure()

    def test_no_snapshot(self):
        with self.assertRaises(NoSnapshot):
            hetzner(FakeApi(snapshots=[])).ensure()

    def test_other_api_errors_are_not_mistaken_for_capacity(self):
        class Broken(FakeApi):
            def __call__(self, method, path, body=None):
                if method == "POST":
                    raise ApiError(401, "unauthorized")
                return super().__call__(method, path, body)

        with self.assertRaises(ApiError):
            hetzner(Broken()).ensure()


class Exists(unittest.TestCase):
    def test_exists(self):
        self.assertTrue(hetzner(FakeApi(servers=[SERVER])).exists())
        self.assertFalse(hetzner(FakeApi()).exists())


if __name__ == "__main__":
    unittest.main()
