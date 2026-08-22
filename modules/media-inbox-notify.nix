# Notifies via ntfy.sh when someone new onboards to media-inbox.
#
# Polls the InstantDB admin query API every 5 minutes and compares the set of
# $users ids against a state file. Notify-then-persist ordering: a crash
# between the two re-notifies on the next run instead of silently dropping a
# signup. First run seeds the state file and sends a single bootstrap message
# rather than one per pre-existing user.
{ config, pkgs, ... }:
let
  instantAppId = "4d9d32c8-0766-4dad-9b3a-3068a405e693";
  notifyScript = pkgs.writeShellApplication {
    name = "media-inbox-notify";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      set -a
      # shellcheck disable=SC1091
      source "$CREDENTIALS_DIRECTORY/env"
      set +a

      state="$STATE_DIRECTORY/seen-users.json"

      # shellcheck disable=SC2016 # $users is literal JSON, not a shell variable
      current=$(curl -sS --fail-with-body \
        -X POST "https://api.instantdb.com/admin/query?app_id=${instantAppId}" \
        -H "Authorization: Bearer $INSTANT_APP_ADMIN_TOKEN" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"$users":{}}}' \
        | jq '[.["$users"][] | {id, email}]')

      notify() {
        curl -sS --fail-with-body \
          -H "Title: media-inbox" -H "Tags: wave" \
          -d "$1" "https://ntfy.sh/$NTFY_TOPIC" > /dev/null
      }

      if [ ! -f "$state" ]; then
        notify "Onboarding notifications initialized. Tracking $(jq 'length' <<< "$current") existing users."
        echo "$current" > "$state"
        exit 0
      fi

      new=$(jq --slurpfile seen "$state" \
        '[.[] | select(.id as $i | $seen[0] | map(.id) | index($i) | not)]' \
        <<< "$current")

      jq -r '.[] | "\(.email // .id) just onboarded to media-inbox 🎉"' <<< "$new" \
        | while IFS= read -r message; do notify "$message"; done

      # Union rather than overwrite: a user deleted upstream stays "seen".
      # Temp + rename: `> "$state"` would truncate the file before jq slurps it.
      jq --slurpfile seen "$state" '. + $seen[0] | unique_by(.id)' \
        <<< "$new" > "$state.tmp"
      mv "$state.tmp" "$state"
    '';
  };
in
{
  clan.core.vars.generators.media-inbox-notify = {
    files."env_file" = { };
    prompts."admin-token" = {
      type = "line";
      description = "The InstantDB admin token for media-inbox";
    };
    prompts."ntfy-topic" = {
      type = "line";
      description = "The (secret) ntfy.sh topic for media-inbox notifications";
    };
    script = ''
      {
        echo "INSTANT_APP_ADMIN_TOKEN=$(cat $prompts/admin-token)"
        echo "NTFY_TOPIC=$(cat $prompts/ntfy-topic)"
      } > "$out/env_file"
    '';
  };

  systemd.services.media-inbox-notify = {
    description = "Notify about new media-inbox users";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "media-inbox-notify";
      LoadCredential = [
        "env:${config.clan.core.vars.generators.media-inbox-notify.files.env_file.path}"
      ];
      ExecStart = "${notifyScript}/bin/media-inbox-notify";
    };
  };

  systemd.timers.media-inbox-notify = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
      RandomizedDelaySec = "30s";
    };
  };
}
