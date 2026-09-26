# Static checks of the monitoring config, no VM: vmalert parses the rules,
# vmalert-tool runs their unit tests, and every vmui dashboard query is
# parsed as MetricsQL (wrapped as a recording rule for `vmalert -dryRun`).
{ pkgs, lib }:
let
  yaml = pkgs.formats.yaml { };
  groups = import ../modules/metrics/rules.nix;
  rulesFile = yaml.generate "rules.yaml" { inherit groups; };
  dashboards = import ../modules/metrics/dashboards.nix { inherit pkgs lib; };
  expected = [
    "mail"
    "overview"
    "todos"
  ];
  exprs = lib.concatMap (
    d: lib.concatMap (row: lib.concatMap (panel: panel.expr) row.panels) d.rows
  ) (builtins.attrValues dashboards.all);
  queriesFile = yaml.generate "dashboard-queries.yaml" {
    groups = [
      {
        name = "dashboard-queries";
        rules = lib.imap0 (i: expr: {
          record = "dashboard_query_${toString i}";
          inherit expr;
        }) exprs;
      }
    ];
  };
in
assert lib.assertMsg (
  builtins.attrNames dashboards.all == expected
) "dashboards: expected ${toString expected}, got ${toString (builtins.attrNames dashboards.all)}";
pkgs.runCommand "metrics-config"
  {
    nativeBuildInputs = [
      pkgs.victoriametrics
      pkgs.jq
    ];
  }
  ''
    cp ${rulesFile} rules.yaml
    cp ${./metrics-config/alerts.test.yaml} alerts.test.yaml
    vmalert -dryRun -rule=rules.yaml
    vmalert-tool unittest --disableAlertgroupLabel --files=alerts.test.yaml

    # vmui only needs rows of panels with at least one expr each.
    for f in ${dashboards.dir}/*.json; do
      jq -e '(.rows | length > 0) and all(.rows[].panels[]; (.expr | length > 0) and .title)' "$f" \
        || { echo "bad dashboard: $f"; exit 1; }
    done
    vmalert -dryRun -rule=${queriesFile}
    touch $out
  ''
