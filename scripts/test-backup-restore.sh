#!/usr/bin/env bash
# Run on Gondor as root after activating the rehearsal configuration.
# Uses its pinned driver, private runtime state, retrieval and notifications.
set -euo pipefail
if [ "$#" -ne 0 ]; then
  echo "Usage: $0 (on Gondor as root)" >&2
  exit 2
fi
# systemctl start waits for the oneshot and propagates its failure.
exec systemctl start todo-home-backup-test.service
