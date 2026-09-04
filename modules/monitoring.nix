# External uptime probe for todos.humane.tools (see
# todo-home/docs/design/monitoring.md for the health endpoints it hits).
#
# Gatus runs here on formenos, outside orthanc, so a dead host still gets
# reported. Alerts go to a secret topic on the public ntfy.sh; the ntfy app
# on the phone subscribes to that topic. The dashboard binds to localhost
# only — reach it with `ssh -L 8085:127.0.0.1:8085 formenos`.
{ config, ... }:
{
  # Same shape as media-inbox-notify: the topic is prompted once and reaches
  # the service through an environment file, never the nix store. It is the
  # only secret: whoever knows it can read alerts and post fakes, so use a
  # long random string.
  clan.core.vars.generators.gatus = {
    files."env_file" = { };
    prompts."ntfy-topic" = {
      type = "line";
      description = "The (secret) ntfy.sh topic that pages when todos.humane.tools is down";
    };
    script = ''
      echo "NTFY_TOPIC=$(cat $prompts/ntfy-topic)" > "$out/env_file"
    '';
  };

  services.gatus = {
    enable = true;
    environmentFile = config.clan.core.vars.generators.gatus.files.env_file.path;
    settings = {
      web = {
        address = "127.0.0.1";
        port = 8085;
      };
      # Keep history across restarts; the module gives us /var/lib/gatus.
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };
      alerting.ntfy = {
        url = "https://ntfy.sh";
        topic = "\${NTFY_TOPIC}";
        # 5 = max: the ntfy app plays the urgent sound. Prod is a pager.
        priority = 5;
        click = "https://todos.humane.tools/";
        default-alert = {
          enabled = true;
          # 60s interval × 3 failures: a page after about three minutes down,
          # and a single dropped probe stays quiet.
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
        # Dev down is a note, not a page.
        overrides = [
          {
            group = "dev.todos.humane.tools";
            priority = 3;
            click = "https://dev.todos.humane.tools/";
          }
        ];
      };
      endpoints =
        let
          probe = domain: name: path: conditions: {
            inherit name conditions;
            group = domain;
            url = "https://${domain}${path}";
            interval = "60s";
            alerts = [ { type = "ntfy"; } ];
          };
          instance = domain: [
            # Caddy + frontend files + TLS certificate.
            (probe domain "app" "/" [
              "[STATUS] == 200"
              "[CERTIFICATE_EXPIRATION] > 168h"
            ])
            # better-auth built-in liveness on the auth port.
            (probe domain "auth" "/api/auth/ok" [ "[STATUS] == 200" ])
            # Our health report: auth DB, doc_state table, sync server listening.
            (probe domain "sync" "/sync/healthz" [
              "[STATUS] == 200"
              "[BODY].ok == true"
            ])
          ];
        in
        instance "todos.humane.tools" ++ instance "dev.todos.humane.tools";
    };
  };
}
