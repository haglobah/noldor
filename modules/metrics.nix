# Metrics and logs backend on formenos.
#
# - VictoriaMetrics (metrics, 90 days) scrapes formenos itself and receives
#   remote-write from other machines.
# - VictoriaLogs (logs, 30 days) receives journald from formenos and from
#   other machines.
# - vmalert evaluates ./metrics/rules.nix; Alertmanager posts to the same
#   ntfy topic Gatus pages on, formatted by ntfy's built-in `alertmanager`
#   template.
# - vmui (VictoriaMetrics' own UI) shows the dashboards from
#   ./metrics/dashboards.nix; VictoriaLogs has its own UI for logs.
# - checks.metrics-config unit-tests the rules and parses every dashboard
#   query; checks.metrics-backend runs them in a VM.
#
# Everything binds to 127.0.0.1. `just dash` tunnels the UIs to gondor.
# Other machines ship through the ingest host (./metrics-ingest.nix), which
# only exposes the write paths, behind basic auth (./metrics-ingest-secret.nix).
{
  config,
  pkgs,
  lib,
  ...
}:
let
  machine = "formenos";
  ports = {
    victoriametrics = 8428;
    victorialogs = 9428;
    vmalert = 8880;
    alertmanager = 9093;
    node = 9100;
    caddyAdmin = 2019;
    gatus = 8085;
  };
  local = port: "127.0.0.1:${toString port}";

  inherit (import ./metrics-ingest.nix) ingestHost;
  dashboards = import ./metrics/dashboards.nix { inherit pkgs lib; };

  scrape = job: port: {
    job_name = job;
    static_configs = [ { targets = [ (local port) ]; } ];
  };
  # Every series carries the machine it describes. Shippers on other
  # machines set the same label (machine="orthanc"). Not `host`:
  # Caddy's per_host metrics already use that for the virtual host.
  machineLabel = {
    target_label = "machine";
    replacement = machine;
  };
in
{
  imports = [ ./metrics-ingest-secret.nix ];

  services.victoriametrics = {
    enable = true;
    listenAddress = local ports.victoriametrics;
    retentionPeriod = "90d";
    extraOptions = [
      # 4 GB box shared with Immich and Paperless. The default is 60%.
      "-memory.allowedPercent=15"
      "-vmui.customDashboardsPath=${dashboards.dir}"
    ];
    prometheusConfig = {
      global.scrape_interval = "30s";
      scrape_configs = map (c: c // { relabel_configs = [ machineLabel ]; }) [
        (scrape "node" ports.node)
        (scrape "caddy" ports.caddyAdmin)
        (scrape "victoriametrics" ports.victoriametrics)
        (scrape "victorialogs" ports.victorialogs)
        (scrape "vmalert" ports.vmalert)
        (scrape "alertmanager" ports.alertmanager)
        (scrape "gatus" ports.gatus)
      ];
    };
  };

  services.victorialogs = {
    enable = true;
    listenAddress = local ports.victorialogs;
    extraOptions = [
      "-retentionPeriod=30d"
      # 11 GB free on / at setup time; never let logs take more than 3 GiB.
      "-retention.maxDiskSpaceUsageBytes=3GiB"
      "-memory.allowedPercent=10"
    ];
  };

  # formenos' own journal goes straight into VictoriaLogs' journald endpoint.
  services.journald.upload = {
    enable = true;
    settings.Upload.URL = "http://${local ports.victorialogs}/insert/journald";
  };

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = ports.node;
    enabledCollectors = [ "systemd" ];
  };

  # Caddy serves Prometheus metrics on its admin endpoint (127.0.0.1:2019).
  # per_host adds a `host` label to the HTTP metrics.
  services.caddy.globalConfig = ''
    metrics {
      per_host
    }
  '';

  services.gatus.settings.metrics = true;

  services.vmalert.instances."" = {
    enable = true;
    settings = {
      "datasource.url" = "http://${local ports.victoriametrics}";
      "remoteWrite.url" = "http://${local ports.victoriametrics}";
      "remoteRead.url" = "http://${local ports.victoriametrics}";
      "notifier.url" = [ "http://${local ports.alertmanager}" ];
      "httpListenAddr" = local ports.vmalert;
      "external.url" = "http://localhost:${toString ports.vmalert}";
    };
    rules.groups = import ./metrics/rules.nix;
  };

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = ports.alertmanager;
    # NTFY_TOPIC, from the same generator Gatus uses (./monitoring.nix).
    environmentFile = config.clan.core.vars.generators.gatus.files.env_file.path;
    # The topic is substituted at start, so the checker sees a placeholder.
    checkConfig = false;
    configuration = {
      route = {
        receiver = "ntfy-warn";
        group_by = [
          "alertname"
          "machine"
        ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "12h";
        routes = [
          {
            receiver = "ntfy-page";
            matchers = [ ''severity="page"'' ];
          }
        ];
      };
      receivers =
        let
          ntfy = name: priority: {
            inherit name;
            webhook_configs = [
              {
                url = "https://ntfy.sh/\${NTFY_TOPIC}?template=alertmanager&priority=${toString priority}";
                send_resolved = true;
              }
            ];
          };
        in
        [
          (ntfy "ntfy-page" 5)
          (ntfy "ntfy-warn" 3)
        ];
    };
  };

  # Ingest for other machines. Only the write paths are reachable; the
  # UIs and query APIs stay on localhost.
  services.caddy.environmentFile =
    config.clan.core.vars.generators.metrics-ingest.files.caddy_env.path;
  services.caddy.virtualHosts.${ingestHost}.extraConfig = ''
    @write path /api/v1/write
    @logs path /insert/journald/* /insert/jsonline /insert/loki/api/v1/push
    handle @write {
      basic_auth {
        ingest {$METRICS_INGEST_HASH}
      }
      reverse_proxy ${local ports.victoriametrics}
    }
    handle @logs {
      basic_auth {
        ingest {$METRICS_INGEST_HASH}
      }
      reverse_proxy ${local ports.victorialogs}
    }
    handle {
      respond 404
    }
  '';
}
