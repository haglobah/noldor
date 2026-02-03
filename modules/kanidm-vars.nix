# Kanidm Secrets Generator
# Generates admin passwords and self-signed TLS certificates for Kanidm
{ config, pkgs, ... }:
{
  clan.core.vars.generators.kanidm = {
    files."admin-password" = {
      owner = "kanidm";
      group = "kanidm";
    };
    files."idm-admin-password" = {
      owner = "kanidm";
      group = "kanidm";
    };
    # Self-signed TLS certificates for Kanidm's internal HTTPS
    # Caddy handles the real TLS termination; these are for localhost only
    files."tls-key" = {
      owner = "kanidm";
      group = "kanidm";
      mode = "0600";
    };
    files."tls-chain" = {
      owner = "kanidm";
      group = "kanidm";
      mode = "0644";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 > "$out"/admin-password
      openssl rand -base64 32 > "$out"/idm-admin-password

      # Generate self-signed TLS certificates for Kanidm's internal HTTPS
      openssl req -x509 -newkey rsa:4096 \
        -keyout "$out"/tls-key \
        -out "$out"/tls-chain \
        -sha256 -days 3650 -nodes \
        -subj "/CN=idm.hagenlocher.me" \
        -addext "subjectAltName=DNS:idm.hagenlocher.me,DNS:localhost,IP:127.0.0.1"
    '';
  };
}
