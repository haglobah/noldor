"""Hetzner Cloud: find or create the builder from its newest snapshot.

Hetzner bills every started hour while a server exists, even powered off.
The builder deletes itself when idle (its reaper); this side only creates.
"""

import json
import urllib.error
import urllib.request

API = "https://api.hetzner.cloud/v1"


class ApiError(Exception):
    def __init__(self, status: int, code: str):
        super().__init__(f"Hetzner API: HTTP {status} {code}")
        self.status = status
        self.code = code


class NoSnapshot(Exception):
    pass


class NoCapacity(Exception):
    pass


# Codes Hetzner answers when a type is sold out or not offered somewhere.
CAPACITY_CODES = {
    "resource_unavailable",
    "server_type_unavailable",
    "placement_error",
    "unsupported_location",
}


def http_api(token: str):
    def call(method: str, path: str, body=None):
        req = urllib.request.Request(
            API + path,
            method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
        except urllib.error.HTTPError as e:
            try:
                code = json.loads(e.read())["error"]["code"]
            except Exception:
                code = "unknown"
            raise ApiError(e.code, code) from None
        return json.loads(data) if data else {}

    return call


class Hetzner:
    def __init__(self, api, name: str, types: list, locations: list):
        self.api = api
        self.name = name
        self.types = types
        self.locations = locations
        self.label = f"machine={name}"

    def server(self):
        got = self.api("GET", f"/servers?label_selector={self.label}")
        matches = [s for s in got["servers"] if s["name"] == self.name]
        return matches[0] if matches else None

    def exists(self) -> bool:
        return self.server() is not None

    def ensure(self) -> str:
        """The builder's IPv4 address, creating the server if needed."""
        server = self.server()
        if server is None:
            server = self._create()
        return server["public_net"]["ipv4"]["ip"]

    def _create(self):
        images = self.api("GET", f"/images?type=snapshot&label_selector={self.label}")[
            "images"
        ]
        if not images:
            raise NoSnapshot(
                f"no snapshot labelled {self.label}; bootstrap aule first (docs/nix-builder.md)"
            )
        image = max(images, key=lambda i: i["created"])["id"]
        refused = []
        for server_type in self.types:
            for location in self.locations:
                try:
                    return self.api(
                        "POST",
                        "/servers",
                        {
                            "name": self.name,
                            "server_type": server_type,
                            "location": location,
                            "image": str(image),
                            "labels": {"machine": self.name},
                        },
                    )["server"]
                except ApiError as e:
                    if e.code not in CAPACITY_CODES:
                        raise
                    refused.append(f"{server_type}/{location}: {e.code}")
        raise NoCapacity("no server type available: " + ", ".join(refused))
