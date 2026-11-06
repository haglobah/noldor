# The `notable` client secret of the humane.tools accounts provider (ht's
# ADR-005; Notable's ADR-001 "humane tools sign-in through the accounts
# provider"): Todos' auth process on orthanc registers the client with it,
# Notable's server on formenos signs in with it.
#
# Shared, so both machines hold the same generated value. Import this module
# on both sides (./humane-accounts.nix, ./notable.nix). Both files reach both
# machines; each side loads only its own.
{ pkgs, ... }:
{
  clan.core.vars.generators.humane-accounts-notable = {
    share = true;
    files = {
      # For todo-home prod's envFiles.
      "todo_env" = { };
      # For notable-server's environmentFile.
      "notable_env" = { };
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      secret=$(openssl rand -hex 32)
      echo "OIDC_NOTABLE_CLIENT_SECRET=$secret" > "$out/todo_env"
      echo "NOTABLE_OIDC_CLIENT_SECRET=$secret" > "$out/notable_env"
    '';
  };
}
