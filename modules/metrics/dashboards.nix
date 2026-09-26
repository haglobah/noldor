# vmui dashboards (the "Dashboards" tab of VictoriaMetrics' web UI),
# served from -vmui.customDashboardsPath in ../metrics.nix. vmui has no
# variables: each panel shows every instance, split by the legend.
# Schema: app/vmui/packages/vmui/README.md, "Predefined dashboards".
#
# Logs have no dashboard; use VictoriaLogs' own UI (`just dash`, then
# http://localhost:19428/select/vmui). Useful LogsQL queries — formenos
# ships raw journald fields, orthanc Vector's (machine, unit, priority):
#
#   errors on orthanc:      _stream:{machine="orthanc"} priority:<=3
#   errors on formenos:     _HOSTNAME:formenos PRIORITY:<=3
#   one unit on orthanc:    _stream:{machine="orthanc",unit="todo-home-prod.service"}
#   updater runs:           unit:~"-updater" | sort by (_time) desc
#   rollbacks and soaks:    unit:~"-updater" ("Rolled back" or "soak window")
#   error count per unit:   priority:<=3 | stats by (machine, unit) count() errors
{ pkgs, lib }:
let
  panel =
    title: expr: extra:
    {
      inherit title;
      expr = lib.toList expr;
      width = 6;
    }
    // extra;
  row = title: panels: { inherit title panels; };

  apps = ''job=~"todos|mail"'';
  vhosts = ''machine="orthanc", host=~"(dev\\.)?(todos|mail)\\.humane\\.tools"'';
  requests =
    extra: "sum by (host) (rate(caddy_http_request_duration_seconds_count{${vhosts}${extra}}[5m]))";
  perInstance.alias = [ "{{app}} {{instance}}" ];
  bytes.unit = "bytes";

  all = {
    overview.rows = [
      (row "Apps" [
        (panel "Metrics up" "up{${apps}}" perInstance)
        (panel "Running commit"
          ''max by (app, instance, commit) ({__name__=~"todo_home_build_info|humane_mail_build_info"})''
          {
            alias = [ "{{app}} {{instance}} {{commit}}" ];
          }
        )
        (panel "Requests/s" (requests "") { })
        (panel "5xx %" "100 * ${requests '', code=~"5.."''} / ${requests ""}" { unit = "%"; })
        (panel "p95 latency (no WebSockets)"
          ''histogram_quantile(0.95, sum by (host, le) (rate(caddy_http_request_duration_seconds_bucket{${vhosts}, code!="101"}[5m])))''
          { unit = "s"; }
        )
        (panel "RSS" "process_resident_memory_bytes{${apps}}" (perInstance // bytes))
      ])
      (row "Hosts" [
        (panel "CPU busy %" ''100 * (1 - avg by (machine) (rate(node_cpu_seconds_total{mode="idle"}[5m])))''
          {
            unit = "%";
          }
        )
        (panel "Memory available %" "100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes" {
          unit = "%";
        })
        (panel "Root disk free %"
          ''100 * node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}''
          {
            unit = "%";
          }
        )
        (panel "Failed units" ''node_systemd_unit_state{state="failed"} == 1'' {
          alias = [ "{{machine}} {{name}}" ];
        })
      ])
    ];

    todos.rows = [
      (row "Sync" [
        (panel "Open sockets" ''todo_home_sync_sockets{job="todos"}'' perInstance)
        (panel "Open docs" ''todo_home_sync_open_docs{job="todos"}'' perInstance)
        (panel "Updates applied/s" ''rate(todo_home_sync_updates_applied_total{job="todos"}[5m])''
          perInstance
        )
        (panel "Updates refused/s"
          ''sum by (instance, reason) (rate(todo_home_sync_updates_refused_total{job="todos"}[5m]))''
          {
            alias = [ "{{instance}} {{reason}}" ];
          }
        )
      ])
      (row "Storage and process" [
        (panel "doc_state size" ''todo_home_doc_state_bytes{job="todos"}'' (perInstance // bytes))
        (panel "Auth DB size (+WAL)" ''todo_home_auth_db_bytes{job="todos"}'' (perInstance // bytes))
        (panel "Event loop lag p99" ''nodejs_eventloop_lag_p99_seconds{job="todos"}'' (
          perInstance // { unit = "s"; }
        ))
      ])
    ];

    mail.rows = [
      (row "Accounts" [
        (panel "Accounts by state" ''humane_mail_accounts{job="mail"}'' {
          alias = [ "{{instance}} {{state}}" ];
        })
        (panel "Oldest sync age" ''humane_mail_sync_age_seconds{job="mail"}'' (
          perInstance // { unit = "s"; }
        ))
        (panel "Worker spawn errors (1h)" ''increase(humane_mail_worker_errors_total{job="mail"}[1h])''
          perInstance
        )
      ])
      (row "Sending" [
        (panel "Outbox by status" ''humane_mail_outbox{job="mail"}'' {
          alias = [ "{{instance}} {{status}}" ];
        })
        (panel "Send status changes (1h)"
          ''sum by (instance, status) (increase(humane_mail_send_status_total{job="mail"}[1h]))''
          {
            alias = [ "{{instance}} {{status}}" ];
          }
        )
      ])
      (row "Storage and process" [
        (panel "Database size (+WAL)" ''humane_mail_db_bytes{job="mail"}'' (
          bytes // { alias = [ "{{instance}} {{db}}" ]; }
        ))
        (panel "Event loop lag p99" ''nodejs_eventloop_lag_p99_seconds{job="mail"}'' (
          perInstance // { unit = "s"; }
        ))
      ])
    ];
  };
in
{
  inherit all;
  dir = pkgs.linkFarm "vmui-dashboards" (
    lib.mapAttrsToList (name: d: {
      name = "${name}.json";
      path = pkgs.writeText "${name}.json" (builtins.toJSON ({ title = name; } // d));
    }) all
  );
}
