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
