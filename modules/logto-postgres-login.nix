{ config, pkgs, ... }:
{

  clan.core.vars.generators.logto-postgres-login = {
    share = true;
    files."envFile" = { };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      # Generate password
      THEPASS=$(openssl rand -hex 32)

      echo "POSTGRES_PASSWORD=$THEPASS" > $out/envFile
      echo "DB_URL=postgres://postgres:$THEPASS@postgres:5432/logto" >> $out/envFile
    '';
  };
}
