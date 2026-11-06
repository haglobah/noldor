# The OIDC client secrets of the humane.tools accounts provider (ht's
# docs/adr/ADR-005), served at accounts.humane.tools by todo-home prod
# (./todo-home.nix, `accountsDomain`). Each client has a generator of its own,
# so each secret can be rotated alone (regenerating one signs that app's users
# in once more, silently while their accounts session lasts).
#
# Production only: dev runs no provider, and Todos and Mail refuse to boot
# with a client secret but no ACCOUNTS_URL.
{ pkgs, ... }:
let
  secret = ''secret=$(openssl rand -hex 32)'';
in
{
  imports = [ ./humane-accounts-notable-secret.nix ];

  clan.core.vars.generators = {
    # Todos is a client of its own auth process.
    humane-accounts-todos = {
      files."todo_env" = { };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        ${secret}
        echo "OIDC_TODOS_CLIENT_SECRET=$secret" > "$out/todo_env"
      '';
    };
    # Mail: the provider (todo-home) and the client (humane-mail) hold the
    # same value, both on orthanc.
    humane-accounts-mail = {
      files."todo_env" = { };
      files."mail_env" = { };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        ${secret}
        echo "OIDC_MAIL_CLIENT_SECRET=$secret" > "$out/todo_env"
        echo "OIDC_MAIL_CLIENT_SECRET=$secret" > "$out/mail_env"
      '';
    };
  };
}
