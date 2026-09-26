# Basic-auth credential for the metrics/logs ingest endpoint on formenos
# (host in ./metrics-ingest.nix, served by ./metrics.nix).
#
# Shared, so formenos (Caddy checks the hash) and every shipping machine
# (sends the password) hold the same generated value. Import this module on
# both sides. The user name is fixed and not secret: "ingest".
{ pkgs, ... }:
{
  clan.core.vars.generators.metrics-ingest = {
    share = true;
    files = {
      # Plaintext password for the shippers (vmagent, log shipper).
      "password" = { };
      # METRICS_INGEST_HASH=<bcrypt>, loaded into Caddy's environment.
      "caddy_env" = { };
    };
    runtimeInputs = [
      pkgs.caddy
      pkgs.openssl
    ];
    script = ''
      openssl rand -hex 32 | tr -d '\n' > "$out/password"
      echo "METRICS_INGEST_HASH=$(caddy hash-password --plaintext "$(cat "$out/password")")" > "$out/caddy_env"
    '';
  };
}
