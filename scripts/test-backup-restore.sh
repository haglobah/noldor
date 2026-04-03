#!/usr/bin/env bash
# Tests that the latest todo-home backup can be restored into a fresh
# NixOS VM and the service starts correctly with the restored data.
#
# Prerequisites: clan CLI, borg, SSH access to storagebox (key via clan vars)
# Usage: ./scripts/test-backup-restore.sh
set -euo pipefail

NOLDOR_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MOUNTDIR=$(mktemp -d)
TMPKEY=$(mktemp)
DATATAR=$(mktemp --suffix=.tar)
trap 'borg umount "$MOUNTDIR" 2>/dev/null; rm -rf "$MOUNTDIR" "$TMPKEY" "$DATATAR"' EXIT

BORG_REPO="u366465-sub5@u366465-sub5.your-storagebox.de:/./borgbackup/orthanc"

# Get credentials from clan vars
echo "=== Fetching credentials ==="
cd "$NOLDOR_DIR"
clan vars get orthanc borgbackup/borgbackup.ssh > "$TMPKEY"
chmod 600 "$TMPKEY"
export BORG_RSH="ssh -p 23 -oStrictHostKeyChecking=accept-new -i $TMPKEY"
export BORG_PASSPHRASE=$(clan vars get orthanc borgbackup/borgbackup.repokey)

echo "=== Getting latest backup name ==="
BACKUP_LINE=$(clan backups list orthanc | tail -1)
BACKUP_NAME=$(echo "$BACKUP_LINE" | awk -F'::' '{print $NF}')
echo "Latest backup: $BACKUP_NAME"

echo "=== Mounting backup from storagebox to $MOUNTDIR ==="
borg mount "$BORG_REPO"::"$BACKUP_NAME" "$MOUNTDIR"

ls -la $MOUNTDIR/var/lib/todo-home

echo "=== Packing backup data ==="
tar cf "$DATATAR" -C "$MOUNTDIR/var/lib/todo-home" .
chmod 644 "$DATATAR"
borg umount "$MOUNTDIR"
echo "Backup tar: $DATATAR"

echo "=== Running NixOS backup restore test ==="
nix build --impure --option sandbox false --no-link --expr "
  let
    todo-home = builtins.getFlake \"git+ssh://git@github.com/haglobah/todo-home.git\";
    nixpkgs = builtins.getFlake \"github:NixOS/nixpkgs/nixos-unstable\";
    pkgs = import nixpkgs { system = \"x86_64-linux\"; };
  in import todo-home.lib.backupTest {
    inherit pkgs;
    frontend = todo-home.packages.x86_64-linux.frontend;
    backend = todo-home.packages.x86_64-linux.backend;
    todoHomeModule = todo-home.nixosModules.default;
    backupDataPath = \"$DATATAR\";
  }
"

echo "=== Backup restore test PASSED ==="
