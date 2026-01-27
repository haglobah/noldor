# Kanidm Admin Password Generator
# Generates both admin and idm_admin passwords for Kanidm provisioning
{ config, pkgs, ... }:
{
  clan.core.vars.generators.kanidm = {
    files."admin-password" = {
      owner = "kanidm";
      group = "kanidm";
    };
    files."idm-admin-password" = {
      owner = "kanidm";
      group = "kanidm";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 > "$out"/admin-password
      openssl rand -base64 32 > "$out"/idm-admin-password
    '';
  };
}
