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
  # Kanidm database (identity data)
  clan.core.state.kanidm = {
    folders = [
      "/var/lib/kanidm"
    ];
  };

  services.caddy = {
    enable = true;
    # Kanidm Identity Provider
    # Kanidm uses HTTPS internally, so we need to handle that
    virtualHosts."idm.hagenlocher.me" = {
      extraConfig = ''
        reverse_proxy https://127.0.0.1:8443 {
          transport http {
            tls
            tls_insecure_skip_verify
          }
        }
      '';
    };
  };
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
      tls_chain = config.clan.core.vars.generators.kanidm.files."tls-chain".path;
      tls_key = config.clan.core.vars.generators.kanidm.files."tls-key".path;
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
          members = [ ];
        };
      };

      persons = {
        "haglobah" = {
          present = true;
          mailAddresses = [ "bah@posteo.de" ];
          groups = [ "todo-app-users" ];
          displayName = "beat.";
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
      };
    };
  };

}
