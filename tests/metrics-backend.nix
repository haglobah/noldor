# VM test of modules/metrics.nix and modules/metrics-shipper.nix: the
# ingest endpoint only accepts authenticated writes, data lands in
# VictoriaMetrics and VictoriaLogs, vmui serves the dashboards and every
# panel query runs, Alertmanager gets the ntfy topic substituted, and a
# second machine ships its metrics and journal end to end.
{ pkgs, lib, ... }:
let
  inherit (import ../modules/metrics-ingest.nix) ingestHost;
  # clan.core.vars stub: every generator file lives under /etc/test-secrets.
  varsStub = {
    options.clan.core.vars.generators = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          let
            generator = name;
          in
          {
            freeformType = lib.types.attrsOf lib.types.anything;
            options.files = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule (
                  { name, ... }:
                  {
                    freeformType = lib.types.attrsOf lib.types.anything;
                    options.path = lib.mkOption {
                      type = lib.types.str;
                      default = "/etc/test-secrets/${generator}/${name}";
                    };
                  }
                )
              );
              default = { };
            };
          }
        )
      );
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "metrics-backend";
  nodes.formenos = {
    networking.firewall.allowedTCPPorts = [ 443 ];
    imports = [
      varsStub
      ../modules/metrics.nix
    ];
    virtualisation.memorySize = 2048;
    # Defined by ./monitoring.nix on the real machine.
    clan.core.vars.generators.gatus.files.env_file = { };
    services.caddy.enable = true;
    # No ACME in the sandbox; Caddy's internal CA signs the vhost.
    services.caddy.globalConfig = "local_certs";
    networking.hosts."127.0.0.1" = [ ingestHost ];
    environment.etc = {
      # bcrypt of "testpw"
      "test-secrets/metrics-ingest/caddy_env".text = ''
        METRICS_INGEST_HASH=$2a$14$m6v3zvQJ1zPjda8b4qCgwO1ocwrNsSxeOd8zKYx03/E99Zjrr.dQi
      '';
      "test-secrets/gatus/env_file".text = "NTFY_TOPIC=testtopic\n";
    };
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
  };

  nodes.orthanc =
    { nodes, ... }:
    {
      imports = [
        varsStub
        ../modules/metrics-shipper.nix
      ];
      virtualisation.memorySize = 1536;
      networking.hosts.${nodes.formenos.networking.primaryIPAddress} = [ ingestHost ];
      environment.etc."test-secrets/metrics-ingest/password".text = "testpw";
      # formenos' Caddy signs with its internal CA in the sandbox.
      services.vmagent.extraArgs = [ "-remoteWrite.tlsInsecureSkipVerify" ];
      services.vector.settings.sinks.victorialogs.tls.verify_certificate = false;
      services.caddy.enable = true;
      services.caddy.virtualHosts."http://app.test:8081".extraConfig = "respond ok";
      networking.hosts."127.0.0.1" = [ "app.test" ];
      environment.systemPackages = [ pkgs.curl ];
    };

  testScript = ''
    ingest = "https://${ingestHost}"
    curl = "curl -sk -o /dev/null -w '%{http_code}'"

    start_all()
    for unit in ["vmagent", "vector", "caddy", "prometheus-node-exporter"]:
        orthanc.wait_for_unit(f"{unit}.service")
    for unit in ["victoriametrics", "victorialogs", "vmalert", "alertmanager", "caddy", "prometheus-node-exporter"]:
        formenos.wait_for_unit(f"{unit}.service")
    formenos.wait_for_open_port(443)

    with subtest("ingest requires basic auth"):
        code = formenos.succeed(f"{curl} -X POST {ingest}/insert/jsonline --data-binary '{{}}'")
        assert code == "401", f"unauthenticated logs write: {code}"
        code = formenos.succeed(f"{curl} -X POST {ingest}/api/v1/write --data-binary x")
        assert code == "401", f"unauthenticated metrics write: {code}"
        code = formenos.succeed(f"{curl} -u ingest:wrong -X POST {ingest}/api/v1/write --data-binary x")
        assert code == "401", f"wrong password: {code}"

    with subtest("query APIs and UIs are not exposed"):
        for path in ["/api/v1/query?query=up", "/vmui", "/select/logsql/query?query=*", "/"]:
            code = formenos.succeed(f"{curl} -u ingest:testpw '{ingest}{path}'")
            assert code == "404", f"{path}: {code}"

    with subtest("authenticated log write lands in VictoriaLogs"):
        formenos.succeed(
            "printf '%s\\n' '{\"_msg\":\"helloorthanc\",\"machine\":\"orthanc\"}' | "
            # Without a JSON content type curl sends form encoding, and
            # VictoriaLogs' form parsing swallows the body.
            + "curl -skf -u ingest:testpw -H 'Content-Type: application/stream+json' "
            + f"-X POST '{ingest}/insert/jsonline?_stream_fields=machine' --data-binary @-"
        )
        formenos.wait_until_succeeds(
            "curl -sf 'http://127.0.0.1:9428/select/logsql/query?query=helloorthanc' | grep -q orthanc",
            timeout=60,
        )

    with subtest("authenticated metrics write passes auth"):
        # A real remote-write body is snappy protobuf; garbage must get past
        # Caddy and be rejected by VictoriaMetrics itself (400), not 401/404.
        code = formenos.succeed(f"{curl} -u ingest:testpw -X POST {ingest}/api/v1/write --data-binary x")
        assert code == "400", f"authenticated metrics write: {code}"

    with subtest("formenos' own journal reaches VictoriaLogs"):
        formenos.succeed("logger -t metricstest journalduploadworks")
        formenos.wait_until_succeeds(
            "curl -sf 'http://127.0.0.1:9428/select/logsql/query?query=journalduploadworks' | grep -q metricstest",
            timeout=90,
        )

    with subtest("scraped series carry machine=formenos"):
        formenos.wait_until_succeeds(
            "curl -sf 'http://127.0.0.1:8428/api/v1/query' --data-urlencode "
            + "'query=up{job=\"node\",machine=\"formenos\"}' | jq -e '.data.result[0].value[1] == \"1\"'",
            timeout=120,
        )
        formenos.wait_until_succeeds(
            "curl -sf 'http://127.0.0.1:8428/api/v1/query' --data-urlencode "
            + "'query=up{job=\"caddy\",machine=\"formenos\"}' | jq -e '.data.result[0].value[1] == \"1\"'",
            timeout=120,
        )

    with subtest("vmalert loaded the rules"):
        rules = formenos.succeed("curl -sf http://127.0.0.1:8880/api/v1/rules")
        assert "IngestStale" in rules, rules

    with subtest("alertmanager has the ntfy topic substituted"):
        # The status API redacts webhook URLs; read the substituted file
        # from the unit's private /tmp instead.
        config = formenos.succeed(
            "cat /tmp/systemd-private-*-alertmanager.service-*/tmp/alert-manager-substituted.yaml"
        )
        assert "https://ntfy.sh/testtopic?template=alertmanager&priority=5" in config, config
        assert "https://ntfy.sh/testtopic?template=alertmanager&priority=3" in config, config
        assert "NTFY_TOPIC" not in config, config
        formenos.succeed("curl -sf http://127.0.0.1:9093/-/ready")

    with subtest("vmui serves the dashboards and every panel query runs"):
        import json, shlex

        dashboards = json.loads(formenos.succeed("curl -sf http://127.0.0.1:8428/vmui/custom-dashboards"))
        titles = sorted(d["title"] for d in dashboards["dashboardsSettings"])
        assert titles == ["mail", "overview", "todos"], titles
        for d in dashboards["dashboardsSettings"]:
            for row in d["rows"]:
                for panel in row["panels"]:
                    for expr in panel["expr"]:
                        # 422 on an expression VictoriaMetrics cannot run.
                        formenos.succeed(
                            "curl -sf http://127.0.0.1:8428/api/v1/query --data-urlencode "
                            + shlex.quote(f"query={expr}")
                            + " -o /dev/null"
                        )

    with subtest("documented error queries match both journal shapes"):
        # formenos ships raw journald fields, orthanc Vector's; the LogsQL
        # examples in modules/metrics/dashboards.nix must match each.
        def logs_query(q):
            return (
                "curl -sf http://127.0.0.1:9428/select/logsql/query --data-urlencode "
                + shlex.quote(f"query={q}")
            )

        formenos.succeed("logger -p user.err -t metricstest formenoserrline")
        orthanc.succeed("logger -p user.err -t errtest orthancerrline")
        formenos.wait_until_succeeds(
            logs_query("_HOSTNAME:formenos PRIORITY:<=3 formenoserrline") + " | grep -q formenoserrline", timeout=120
        )
        formenos.wait_until_succeeds(
            logs_query('_stream:{machine="orthanc"} priority:<=3 orthancerrline') + " | grep -q orthancerrline",
            timeout=120,
        )
        # An info line must not match the error filter.
        formenos.succeed(logs_query("_HOSTNAME:formenos PRIORITY:<=3 journalduploadworks") + " | wc -c | grep -qx 0")

    def vm_query(q):
        return (
            "curl -sf 'http://127.0.0.1:8428/api/v1/query' --data-urlencode "
            + f"'query={q}' | jq -e '.data.result | length > 0'"
        )

    with subtest("orthanc's metrics arrive with machine=orthanc"):
        formenos.wait_until_succeeds(vm_query('up{job="node",machine="orthanc"} == 1'), timeout=120)
        formenos.wait_until_succeeds(vm_query('up{job="caddy",machine="orthanc"} == 1'), timeout=120)
        formenos.wait_until_succeeds(vm_query('up{job="vmagent",machine="orthanc"} == 1'), timeout=120)

    with subtest("orthanc's Caddy metrics are split per virtual host"):
        # Real clients reach orthanc on 443 and send a bare Host header.
        # Caddy only names hosts that match a site address exactly; with
        # ":8081" the request would count as "_other".
        orthanc.succeed("curl -sf -H 'Host: app.test' http://127.0.0.1:8081/")
        formenos.wait_until_succeeds(
            vm_query('caddy_http_requests_total{machine="orthanc",host="app.test"}'), timeout=120
        )

    with subtest("orthanc's journal arrives with machine and unit stream fields"):
        orthanc.succeed("systemd-run --wait --unit=shiptest echo orthancjournalline")
        formenos.wait_until_succeeds(
            "curl -sf http://127.0.0.1:9428/select/logsql/query "
            + "--data-urlencode 'query=_stream:{machine=\"orthanc\",unit=\"shiptest.service\"} orthancjournalline' "
            + "| jq -e 'select(._msg == \"orthancjournalline\")'",
            timeout=120,
        )

    with subtest("the ingest password stays out of the store and the command line"):
        orthanc.fail("grep -rl testpw /nix/store/*vector* /nix/store/*prometheusConfig*")
        orthanc.fail("grep -a testpw /proc/$(pidof vmagent)/cmdline")
  '';
}
