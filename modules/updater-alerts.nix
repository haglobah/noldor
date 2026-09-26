# A failed Todo or Mail updater run on orthanc posts to the same secret
# ntfy.sh topic that Gatus pages on (./monitoring.nix). ht's OnFailure unit
# says whether the updater rolled back, and quotes the failed run's log.
#
# The topic is copied once from the gatus var instead of prompted again:
#   clan vars get formenos gatus/env_file | clan vars set orthanc updater-alerts/env_file
{ config, ... }:
let
  notify = priority: {
    enable = true;
    environmentFile = config.clan.core.vars.generators.updater-alerts.files.env_file.path;
    inherit priority;
  };
in
{
  clan.core.vars.generators.updater-alerts = {
    files."env_file" = { };
    prompts."ntfy-topic" = {
      type = "line";
      description = "The (secret) ntfy.sh topic Gatus pages on; see `clan vars get formenos gatus/env_file`";
    };
    script = ''
      echo "NTFY_TOPIC=$(cat $prompts/ntfy-topic)" > "$out/env_file"
    '';
  };

  # Same priorities as Gatus: prod pages (5), dev is a plain note (3).
  services.todo-home.prod.autoUpdate.notify = notify 5;
  services.todo-home.dev.autoUpdate.notify = notify 3;
  services.humane-mail.instances.prod.autoUpdate.notify = notify 5;
  services.humane-mail.instances.dev.autoUpdate.notify = notify 3;
}
