# vmalert rule groups for ../metrics.nix. Unit tests:
# tests/metrics-config/alerts.test.yaml (run by checks.metrics-config).
#
# Severity: `page` goes to ntfy at priority 5, everything else at 3 (see
# the Alertmanager routes in ../metrics.nix). Prod app alerts page, dev
# ones warn. Public uptime is Gatus' job (../monitoring.nix): these rules
# never page for "backend unreachable", so an outage pages once.
let
  appName = "{{ $labels.app }} {{ $labels.instance }}";
  pct = ''{{ printf "%.0f" $value }}'';

  # One rule per instance: prod pages, dev warns. `expr` gets the label
  # matcher that selects the instance.
  perInstance =
    rule:
    map
      (
        { instance, severity }:
        rule
        // {
          expr = rule.expr ''instance="${instance}"'';
          labels.severity = severity;
        }
      )
      [
        {
          instance = "prod";
          severity = "page";
        }
        {
          instance = "dev";
          severity = "warn";
        }
      ];

  # Caddy counts each request per virtual host (per_host). 502 and 504
  # mean Caddy could not reach the backend: Gatus pages for that.
  errorRate =
    severity: hosts:
    let
      requests =
        extra:
        ''sum by (machine, host) (rate(caddy_http_request_duration_seconds_count{host=~"${hosts}"${extra}}[5m]))'';
    in
    {
      alert = "HighErrorRate";
      expr = ''
        (${requests '', code=~"5..", code!~"502|504"''} /${requests ""}) * 100 > 5
        and ${requests ""} > 0.05'';
      "for" = "5m";
      labels.severity = severity;
      annotations.summary = "{{ $labels.host }}: ${pct}% of requests fail with 5xx";
    };
in
[
  {
    name = "pipeline";
    rules = [
      {
        alert = "IngestStale";
        expr = ''absent_over_time(up{machine="orthanc"}[10m])'';
        labels.severity = "page";
        annotations.summary = "No metrics from orthanc for 10 minutes";
      }
    ];
  }
  {
    name = "apps";
    rules = [
      {
        alert = "AppMetricsDown";
        expr = ''up{job=~"todos|mail"} == 0'';
        "for" = "3m";
        labels.severity = "warn";
        annotations.summary = "${appName}: metrics endpoint unreachable for 3m";
      }
      (errorRate "page" ''(todos|mail)\\.humane\\.tools'')
      (errorRate "warn" ''dev\\.(todos|mail)\\.humane\\.tools'')
    ]
    ++ perInstance {
      alert = "MailSyncStale";
      expr = sel: "humane_mail_sync_age_seconds{${sel}} > 1800";
      "for" = "5m";
      annotations.summary = "${appName}: an account has not synced for {{ $value | humanizeDuration }}";
    }
    ++ perInstance {
      alert = "MailOutboxStuck";
      # Messages waited in the outbox for the whole window and nothing
      # went out meanwhile. `unless` also covers a counter that has no
      # "sent" series yet.
      expr = sel: ''
        min_over_time(humane_mail_outbox{${sel}, status=~"queued|sending"}[15m]) > 0
        unless on (job, app, instance, machine)
        increase(humane_mail_send_status_total{${sel}, status="sent"}[15m]) > 0'';
      annotations.summary = "${appName}: ${pct} outbox messages {{ $labels.status }} for 15m with no send";
    }
    ++ perInstance {
      alert = "TodosSyncApplyFailed";
      # A refused update is a client edit the server did not store.
      expr =
        sel: ''increase(todo_home_sync_updates_refused_total{${sel}, reason="apply_failed"}[10m]) > 0'';
      annotations.summary = "${appName}: ${pct} sync updates failed to apply in 10m";
    };
  }
  {
    name = "hosts";
    rules = [
      {
        alert = "HostMemoryLow";
        expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10";
        "for" = "10m";
        labels.severity = "page";
        annotations.summary = "{{ $labels.machine }}: ${pct}% memory available";
      }
      {
        alert = "HostDiskLow";
        expr = ''
          node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|efivarfs"}
          / node_filesystem_size_bytes * 100 < 10'';
        "for" = "15m";
        labels.severity = "page";
        annotations.summary = "{{ $labels.machine }} {{ $labels.mountpoint }}: ${pct}% disk free";
      }
    ];
  }
]
