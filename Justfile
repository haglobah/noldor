formenos:
    clan ssh formenos -c fish

# Build on gondor, not on the 4GB VPS. Only the CLI flag gets special-cased
# to a local build — inventory deploy.buildHost = "localhost" would ssh there.
deploy-formenos:
    clan machines update formenos --build-host localhost

orthanc:
    clan ssh orthanc -c fish

# Same for the other 4GB VPS: orthanc OOMs on nix builds.
deploy-orthanc:
    clan machines update orthanc --build-host localhost

storage-box:
    ssh -p 23 u366465@u366465.your-storagebox.de

# Tunnel the formenos dashboards to localhost. Ctrl-C closes them.
dash:
    @echo "vmui            http://localhost:18428/vmui  (Dashboards tab)"
    @echo "VictoriaLogs    http://localhost:19428/select/vmui"
    @echo "vmalert         http://localhost:18880"
    @echo "Alertmanager    http://localhost:19093"
    @echo "Gatus           http://localhost:18085"
    ssh -N -o ExitOnForwardFailure=yes \
        -L 18428:127.0.0.1:8428 \
        -L 19428:127.0.0.1:9428 \
        -L 18880:127.0.0.1:8880 \
        -L 19093:127.0.0.1:9093 \
        -L 18085:127.0.0.1:8085 \
        formenos

# Only aule pushes to the R2 cache (clanServices/nix-builds). Evaluates
# without building, so a missing output shows as missing.
# Show whether an installable's outputs are in the R2 cache, with signatures.
cache-check installable:
    nix eval --raw {{installable}}.outPath | xargs sudo nix-cache-info

# aule, the on-demand build machine (docs/nix-builder.md). The scheduler on
# orthanc starts it; it deletes itself when idle. Billed per started hour.
# Delete aule now.
builder-down:
    nix-builder down

# Show aule, its snapshots and the address `clan machines update aule` uses.
builder-status:
    nix-builder status

# Boots the old image, deploys the current config (built on aule itself),
# snapshots it, drops older snapshots and deletes the server.
# Bake aule's current config into a new snapshot.
builder-snapshot:
    nix-builder up
    clan machines update aule
    nix-builder snapshot
