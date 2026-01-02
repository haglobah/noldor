{ config, pkgs, ... }:
{

  clan.core.vars.generators.logto-postgres-password = {
    share = true;
    files."password" = { };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      # Generate password
      openssl rand -hex 32 > $out/password
    '';
  };
}
