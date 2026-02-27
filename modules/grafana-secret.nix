{ pkgs, config, ... }:
{
  clan.core.vars.generators.grafana_secret_key = {
    share = true;
    files = {
      "secret_key" = { };
    };
    runtimeInputs = [ pkgs.openssl ];
    script = "openssl rand -hex 32 > $out/secret_key";
  };
  services.grafana.settings.security.secret_key =
    "$__file{/run/credentials/grafana.service/grafana-secret-key}";
  systemd.services.grafana.serviceConfig = {
    LoadCredential = [
      "grafana-secret-key:${config.clan.core.vars.generators.grafana_secret_key.files.secret_key.path}"
    ];
  };
}
