{ config, pkgs, ... }:
{
  clan.core.vars.generators.storagebox-secret = {
    share = true;
    files."secret" = { };
    prompts.storagebox-secret-input.description = "The credentials for my storage box";
  };
  clan.core.vars.generators.storagebox-immich-secret = {
    share = true;
    files."credentials" = { };
    prompts.storagebox-secret-input.description = "The immich storage box credentials";
  };
}
