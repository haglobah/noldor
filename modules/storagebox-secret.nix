{ config, pkgs, ... }:
{

  clan.core.vars.generators.storagebox-secret = {
    share = true;
    files."secret" = { };
    prompts.storagebox-secret-input.description = "The storage box secret";
  };
}
