"""nix-builds: the daemon (`serve`) and the operator CLI (`status`, `retry`).

All state lives in one SQLite file. The webhook thread only verifies and
parses requests and hands events to the main thread, which owns the
database and runs one job at a time.
"""

import argparse
import json
import logging
import os
import queue
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .github import GitHub, app_jwt
from .hetzner import Hetzner, http_api
from .job import run_job
from .nix import Nix
from .ops import Ops
from .scheduler import Scheduler
from .state import State
from .webhook import parse_event, verify_signature

log = logging.getLogger("nix_builds")

MAX_BODY = 25 * 1024 * 1024  # GitHub caps webhook payloads at 25 MB


def read_secret(path: str) -> str:
    with open(path) as f:
        return f.read().strip()


def read_env_file(path: str) -> dict:
    out = {}
    with open(path) as f:
        for line in f:
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                out[k] = v
    return out


def ntfy(url, env_file):
    def notify(title, text, priority):
        if not env_file:
            return
        try:
            topic = read_env_file(env_file)["NTFY_TOPIC"]
            req = urllib.request.Request(
                f"{url.rstrip('/')}/{topic}",
                data=text.encode(),
                headers={"Title": title, "Priority": str(priority), "Tags": "hammer"},
            )
            urllib.request.urlopen(req, timeout=15).close()
        except Exception as e:  # the journal still has it
            log.warning("ntfy post failed: %s", e)

    return notify


def webhook_server(
    listen: str, secret: bytes, events: queue.Queue, wake: threading.Event
):
    host, port = listen.rsplit(":", 1)

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/webhook":
                return self.send_error(404)
            length = int(self.headers.get("Content-Length", 0))
            if length > MAX_BODY:
                return self.send_error(413)
            body = self.rfile.read(length)
            if not verify_signature(
                secret, body, self.headers.get("X-Hub-Signature-256")
            ):
                log.warning(
                    "webhook: bad signature from %s",
                    self.headers.get("X-Forwarded-For", "?"),
                )
                return self.send_error(401)
            try:
                parsed = parse_event(
                    self.headers.get("X-GitHub-Event", ""), json.loads(body)
                )
            except (ValueError, KeyError) as e:
                return self.send_error(400, f"bad payload: {e}")
            for event in parsed:
                events.put(event)
            wake.set()
            self.send_response(202)
            self.end_headers()

        def do_GET(self):
            # A health check for Caddy and Gatus; no repo names, no state.
            if self.path != "/healthz":
                return self.send_error(404)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")

        def log_message(self, fmt, *args):
            log.debug("webhook: " + fmt, *args)

    server = ThreadingHTTPServer((host, int(port)), Handler)
    threading.Thread(target=server.serve_forever, daemon=True, name="webhook").start()
    return server


def serve(config: dict):
    os.makedirs(config["stateDir"], exist_ok=True)
    state = State(os.path.join(config["stateDir"], "state.sqlite"))

    gh_cfg = config["github"]
    github = GitHub(jwt=lambda: app_jwt(gh_cfg["appId"], gh_cfg["privateKeyFile"]))
    hz = config["hetzner"]
    hetzner = Hetzner(
        http_api(read_secret(hz["tokenFile"])),
        name=hz["name"],
        types=hz["types"],
        locations=hz["locations"],
    )
    b = config["builder"]
    nix = Nix(
        system=config["system"],
        cache_store=config["cache"]["store"],
        cache_credentials=config["cache"]["credentialsFile"],
        ssh_key=b["sshKeyFile"],
        known_hosts=b["knownHostsFile"],
        ssh_user=b["user"],
    )
    ops = Ops(github, hetzner, nix, boot_timeout=b["bootTimeout"])
    scheduler = Scheduler(
        github=github,
        state=state,
        run=lambda push: run_job(push, ops),
        notify=ntfy(config["ntfy"]["url"], config["ntfy"].get("environmentFile")),
        tag_pattern=config["tagPattern"],
    )

    events, wake = queue.Queue(), threading.Event()
    webhook_server(
        config["listen"],
        read_secret(gh_cfg["webhookSecretFile"]).encode(),
        events,
        wake,
    )
    log.info(
        "listening on %s, polling every %ss", config["listen"], config["pollInterval"]
    )

    next_poll = 0.0
    while True:
        batch = []
        while not events.empty():
            batch.append(events.get())
        if batch:
            scheduler.handle(batch)
        if time.monotonic() >= next_poll:
            scheduler.poll()
            next_poll = time.monotonic() + config["pollInterval"]
        if scheduler.step():
            continue
        wake.wait(timeout=max(1.0, min(30.0, next_poll - time.monotonic())))
        wake.clear()


def status(config: dict):
    state = State(os.path.join(config["stateDir"], "state.sqlite"))
    print("queue:")
    for repo, ref, sha, running in state.queued():
        print(f"  {'running' if running else 'queued '} {repo} {ref} {sha[:12]}")
    print("recent:")
    for repo, sha, st, detail, at in state.recent():
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(at))
        print(f"  {when} {st:8} {repo} {sha[:12]} {detail}")


def retry(config: dict, repo: str, sha: str):
    state = State(os.path.join(config["stateDir"], "state.sqlite"))
    if not state.forget(repo, sha):
        sys.exit(f"no result for {repo} {sha}")
    print(
        f"forgot {repo} {sha[:12]}; the next poll builds it again if it is still a head"
    )


def main(argv=None):
    p = argparse.ArgumentParser(prog="nix-builds")
    p.add_argument(
        "--config",
        default=os.environ.get("NIX_BUILDS_CONFIG", "/etc/nix-builds/config.json"),
    )
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("serve")
    sub.add_parser("status")
    r = sub.add_parser("retry")
    r.add_argument("repo")
    r.add_argument("sha")
    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    with open(args.config) as f:
        config = json.load(f)
    if args.cmd == "serve":
        serve(config)
    elif args.cmd == "status":
        status(config)
    else:
        # A full sha: results are keyed by it.
        retry(config, args.repo, args.sha)


if __name__ == "__main__":
    main()
