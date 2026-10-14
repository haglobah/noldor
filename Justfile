formenos:
    clan ssh formenos -c fish

# Build on gondor, not on the 4GB VPS. Only the CLI flag gets special-cased
# to a local build — inventory deploy.buildHost = "localhost" would ssh there.
deploy-formenos:
    clan machines update formenos --build-host localhost

orthanc:
    clan ssh orthanc -c fish

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

# gondor pushes what it builds on its own (docs/nix-cache.md); this pushes
# a whole closure on demand, including paths cache.nixos.org already has.
# Build an installable and push its closure, signed, to the R2 cache.
cache-push installable:
    nix build --no-link --print-out-paths {{installable}} | xargs sudo nix-cache push

# Show whether an installable's outputs are in the R2 cache, with signatures.
cache-check installable:
    nix build --no-link --print-out-paths {{installable}} | xargs sudo nix-cache info
