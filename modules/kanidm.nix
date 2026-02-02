# Kanidm Identity Management Service
# Docs: https://kanidm.github.io/kanidm/stable/
# NixOS options: https://search.nixos.org/options?query=services.kanidm
{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.kanidm = {
    enableServer = true;

    package = pkgs.kanidmWithSecretProvisioning_1_8;

    serverSettings = {
      domain = "idm.hagenlocher.me";
      origin = "https://idm.hagenlocher.me";
      # Bind to localhost; Caddy will reverse proxy
      bindaddress = "127.0.0.1:8443";
      # TLS certificates - Kanidm requires HTTPS internally
      # We use self-signed certs since Caddy handles external TLS
      tls_chain = "/var/lib/kanidm/chain.pem";
      tls_key = "/var/lib/kanidm/key.pem";
    };

    # Declarative provisioning of OAuth2 clients and groups
    # This is the "code-first" approach you wanted
    provision = {
      enable = true;
      # Both admin passwords are required for provisioning
      adminPasswordFile = config.clan.core.vars.generators.kanidm.files."admin-password".path;
      idmAdminPasswordFile = config.clan.core.vars.generators.kanidm.files."idm-admin-password".path;

      # Define user groups
      groups = {
        # Users who can access your todo app
        "todo-app-users" = {
          members = [ ]; # Add user IDs here after creating them
        };
      };

      # Define OAuth2/OIDC clients for your applications
      systems.oauth2 = {
        # Your Todo App OAuth2 client
        "todo-app" = {
          displayName = "Automerge Todo App";
          originLanding = "https://todos.hagenlocher.me";
          originUrl = "https://todos.hagenlocher.me";
          enableLocalhostRedirects = true;
          preferShortUsername = true;
          # Public client (SPA) - PKCE is enforced by default for public clients
          public = true;
          # Scopes to allow
          scopeMaps."todo-app-users" = [
            "openid"
            "profile"
            "email"
          ];
        };

        # Add more OAuth2 clients here as needed
        # "paperless" = { ... };
        # "actual" = { ... };
      };
    };
  };

  # Generate self-signed TLS certificates for Kanidm's internal HTTPS
  # Caddy handles the real TLS termination
  systemd.services.kanidm-cert-init = {
    description = "Generate Kanidm self-signed certificates";
    wantedBy = [ "kanidm.service" ];
    before = [ "kanidm.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      CERT_DIR="/var/lib/kanidm"
      mkdir -p "$CERT_DIR"

      if [ ! -f "$CERT_DIR/key.pem" ] || [ ! -f "$CERT_DIR/chain.pem" ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
          -keyout "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/chain.pem" \
          -sha256 -days 3650 -nodes \
          -subj "/CN=idm.hagenlocher.me" \
          -addext "subjectAltName=DNS:idm.hagenlocher.me,DNS:localhost,IP:127.0.0.1"

        chown kanidm:kanidm "$CERT_DIR/key.pem" "$CERT_DIR/chain.pem"
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/chain.pem"
      fi
    '';
  };

  # Ensure kanidm user exists for the cert service
  users.users.kanidm = {
    isSystemUser = true;
    group = "kanidm";
  };
  users.groups.kanidm = { };
}
