# Ships this machine's metrics and logs to the backend on formenos
# (./metrics.nix) through the ingest host (./metrics-ingest.nix).
#
# - node_exporter and Caddy's admin endpoint expose metrics on localhost.
# - vmagent scrapes them and remote-writes to VictoriaMetrics. Every series
#   gets machine="<hostName>", the label formenos' own scrapes carry.
# - Vector reads journald and posts JSON lines to VictoriaLogs, with the
#   stream fields machine and unit.
#
# Both shippers keep a capped on-disk buffer, so a formenos outage delays
# data instead of losing it. When vmagent's buffer is full it drops the
# oldest samples; Vector blocks and journald keeps the entries until it
# catches up.
{ config, lib, ... }:
let
  machine = config.networking.hostName;
  withMetrics = lib.filterAttrs (_: cfg: cfg.enable && cfg.metricsPort != null);
  todosWithMetrics = withMetrics (config.services.todo-home or { });
  mailWithMetrics = withMetrics (config.services.humane-mail.instances or { });
  # One job per app; `instance` names the deployment, not the address.
  appJob = app: instances: {
    job_name = app;
    static_configs = lib.mapAttrsToList (name: cfg: {
      targets = [ (local cfg.metricsPort) ];
      labels = {
        inherit app;
        instance = name;
      };
    }) instances;
  };
  ingest = "https://${(import ./metrics-ingest.nix).ingestHost}";
  ports = {
    node = 9100;
    caddyAdmin = 2019;
    vmagent = 8429;
  };
  local = port: "127.0.0.1:${toString port}";
  scrape = job: port: {
    job_name = job;
    static_configs = [ { targets = [ (local port) ]; } ];
  };
  passwordFile = config.clan.core.vars.generators.metrics-ingest.files.password.path;
in
{
  imports = [ ./metrics-ingest-secret.nix ];

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = ports.node;
    enabledCollectors = [ "systemd" ];
  };

  # Caddy serves Prometheus metrics on its admin endpoint (127.0.0.1:2019).
  # per_host adds a `host` label, so each virtual host has its own series.
  services.caddy.globalConfig = ''
    metrics {
      per_host
    }
  '';

  services.vmagent = {
    enable = true;
    remoteWrite = {
      url = "${ingest}/api/v1/write";
      basicAuthUsername = "ingest";
      basicAuthPasswordFile = passwordFile;
    };
    extraArgs = [
      "-httpListenAddr=${local ports.vmagent}"
      # The buffer lives in /var/cache/vmagent and survives restarts. At
      # a few KB/s, 512 MB covers days of formenos being down; / had 6 GB
      # free at setup time.
      "-remoteWrite.maxDiskUsagePerURL=512MB"
    ];
    prometheusConfig = {
      global = {
        scrape_interval = "30s";
        external_labels.machine = machine;
      };
      scrape_configs = [
        (scrape "node" ports.node)
        (scrape "caddy" ports.caddyAdmin)
        (scrape "vmagent" ports.vmagent)
        # Todos and Mail serve /metrics on their own loopback ports
        # (metricsPort in ./todo-home.nix and ./humane-mail.nix).
        (appJob "todos" todosWithMetrics)
        (appJob "mail" mailWithMetrics)
      ];
    };
  };

  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      data_dir = "/var/lib/vector";
      # Reads files from the unit's credentials directory; the password
      # never enters the store.
      secret.ingest = {
        type = "directory";
        path = "/run/credentials/vector.service";
      };
      sources.journal = {
        type = "journald";
      };
      transforms.shape = {
        type = "remap";
        inputs = [ "journal" ];
        # Keep the fields worth querying; journald attaches ~30 per entry.
        source = ''
          unit = ._SYSTEMD_UNIT || ._SYSTEMD_USER_UNIT || null
          if unit == null && ._TRANSPORT == "kernel" { unit = "kernel" }
          . = {
            "_time": .timestamp,
            "_msg": .message,
            "machine": "${machine}",
            "unit": unit || .SYSLOG_IDENTIFIER || "unknown",
            "priority": .PRIORITY,
            "identifier": .SYSLOG_IDENTIFIER,
            "pid": ._PID,
            "user_unit": ._SYSTEMD_USER_UNIT,
          }
          . = compact(.)
        '';
      };
      sinks.victorialogs = {
        type = "http";
        inputs = [ "shape" ];
        uri = "${ingest}/insert/jsonline?_stream_fields=machine,unit&_msg_field=_msg&_time_field=_time";
        method = "post";
        auth = {
          strategy = "basic";
          user = "ingest";
          password = "SECRET[ingest.password]";
        };
        encoding.codec = "json";
        framing.method = "newline_delimited";
        # The json codec already sends application/json, which works. Stated
        # explicitly because VictoriaLogs silently drops a body it parses
        # as a form and still answers 200.
        request.headers."Content-Type" = "application/stream+json";
        compression = "gzip";
        # Minimum size Vector allows for a disk buffer. Blocking pauses the
        # journald source; the journal keeps the entries meanwhile.
        buffer = {
          type = "disk";
          max_size = 268435488;
          when_full = "block";
        };
      };
    };
  };

  systemd.services.vector.serviceConfig.LoadCredential = [ "password:${passwordFile}" ];
}
