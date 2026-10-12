{ config, pkgs, ... }:
let
  generator = config.clan.core.vars.generators.nix-access-tokens;
in
{
  # Authenticated GitHub API calls for `github:` flake refs (5000 req/h
  # instead of 60). The token comes from the gh keyring, which the
  # bubblewrap sandbox cannot reach, so generate it with:
  #   clan vars generate gondor -g nix-access-tokens --no-sandbox
  # Re-run with -r after `gh auth logout`/`refresh`, which revokes the token.
  clan.core.vars.generators.nix-access-tokens = {
    files."nix.conf" = {
      # The nix client fetches flake inputs as the invoking user.
      owner = "beat";
      mode = "0400";
    };
    runtimeInputs = [ pkgs.gh ];
    script = ''
      token=$(gh auth token)
      if [ -z "$token" ]; then
        echo "gh auth token returned nothing; run 'gh auth login' first" >&2
        exit 1
      fi
      echo "access-tokens = github.com=$token" > $out/nix.conf
    '';
  };

  # `!include` skips a missing file, so nix keeps working before the
  # secret is deployed. A plain `include` would fail instead.
  nix.extraOptions = ''
    !include ${generator.files."nix.conf".path}
  '';
}
