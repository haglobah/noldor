{
  config,
  lib,
  pkgs,
  ...
}:
let
  root = "/var/lib/todo-home-restore-source";
  snapshotData = pkgs.writeScript "todo-home-consistent-snapshot" ''
    #!${pkgs.python3}/bin/python3
    import os, pathlib, sqlite3, tempfile, tarfile, json, time, hashlib
    root = pathlib.Path('${root}')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        tmp = pathlib.Path(tmp)
        started = int(time.time())
        source = pathlib.Path('${config.services.todo-home.prod.dataDir}')
        assert (source / 'auth.sqlite').is_file(), 'Production database missing'
        for db in source.glob('*.sqlite'):
            with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as src, sqlite3.connect(tmp / db.name) as dst:
                src.backup(dst)
                assert dst.execute('PRAGMA integrity_check').fetchall() == [('ok',)], 'SQLite integrity failure'
        # Legacy files are retained for recovery; active v2 documents live in SQLite.
        import shutil
        for doc in source.glob('*.yjs'):
            shutil.copyfile(doc, tmp / doc.name)
        archive = tmp / 'backup.tar'
        with tarfile.open(archive, 'w') as tar:
            for path in sorted(tmp.iterdir()):
                if path != archive:
                    tar.add(path, arcname=path.name)
        with archive.open('rb') as f:
            digest = hashlib.file_digest(f, 'sha256').hexdigest()
        (tmp / 'metadata.json').write_text(json.dumps({'createdAt': started, 'sha256': digest}))
        os.replace(archive, root / 'backup.tar')
        os.replace(tmp / 'metadata.json', root / 'metadata.json')
  '';
  snapshot = pkgs.writeShellScript "todo-home-quiesced-snapshot" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.systemd
        pkgs.util-linux
      ]
    }
    exec 9>/run/lock/todo-home-prod.lock
    flock -w 1800 9
    # Refuse to bless a snapshot of a failed/stopped production instance.
    systemctl is-active --quiet todo-home-prod.service
    trap 'systemctl start todo-home-prod.service' EXIT
    systemctl stop todo-home-prod.service
    ${snapshotData}
    systemctl start todo-home-prod.service
    trap - EXIT
  '';
  fetch = pkgs.writeShellScript "fetch-todo-home-offsite-backup" ''
    set -euo pipefail
    umask 077
    export PATH=${
      lib.makeBinPath [
        pkgs.borgbackup
        pkgs.openssh
        pkgs.coreutils
        pkgs.gnutar
        pkgs.python3
      ]
    }
    export BORG_REPO=${lib.escapeShellArg config.services.borgbackup.jobs.storagebox.repo}
    export BORG_RSH=${lib.escapeShellArg config.services.borgbackup.jobs.storagebox.environment.BORG_RSH}
    export BORG_PASSCOMMAND=${lib.escapeShellArg config.services.borgbackup.jobs.storagebox.encryption.passCommand}
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    borg list --json --glob-archives ${lib.escapeShellArg "${config.services.borgbackup.jobs.storagebox.archiveBaseName}-*"} --sort-by timestamp > "$work/list.json"
    python3 - "$work/list.json" <<'PYTHON'
    import json,sys
    p=sys.argv[1]
    data=json.load(open(p))
    data['archives']=[a for a in data['archives'] if '.checkpoint' not in a['name'] and not a['name'].endswith('.failed')][-1:]
    assert data['archives'], 'No complete Borg archive'
    with open(p,'w') as f: json.dump(data,f)
    PYTHON
    archive=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["archives"][-1]["name"])' "$work/list.json")
    borg extract --stdout "::$archive" var/lib/todo-home-restore-source/backup.tar > "$work/backup.tar"
    borg extract --stdout "::$archive" var/lib/todo-home-restore-source/metadata.json > "$work/metadata.json"
    python3 - "$work" <<'PY'
    import json,sys,pathlib,datetime
    root=pathlib.Path(sys.argv[1])
    archive=json.loads((root/'list.json').read_text())['archives'][-1]
    report=json.loads((root/'metadata.json').read_text())
    report['id']=archive['id']
    report['archiveCreatedAt']=archive['time']
    (root/'metadata.json').write_text(json.dumps(report))
    PY
    tar cf - -C "$work" backup.tar metadata.json
  '';
in
{
  imports = [ ./todo-home-backup-key.nix ];
  clan.core.state.todo-home-restore-source = {
    folders = [ root ];
    preBackupScript = "${snapshot}";
  };
  # Fetch-only capability: no shell, port forwarding, PTY or caller-supplied args.
  users.users.root.openssh.authorizedKeys.keys = [
    ''restrict,command="${fetch}" ${
      config.clan.core.vars.generators.todo-home-backup-transport.files."key.pub".value
    }''
  ];
}
