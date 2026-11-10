# Wraps an Electron app so it only starts while its safe-storage password in
# the GNOME keyring can be read.
#
# Electron encrypts an app's local secrets (Signal's database key, Slack's and
# Obsidian's logins) with a password it keeps in the keyring. A fingerprint
# login doesn't unlock the keyring, and an app started against the locked
# keyring doesn't find its password, makes a new one and writes it over the
# old one: whatever the old password encrypted is lost for good.
#
# The gate looks the item up first. Locked: it asks GNOME to unlock it (the
# keyring password prompt) and starts the app only once that worked. No item
# at all: a first start, the app makes one.
{
  lib,
  writeShellScript,
  symlinkJoin,
  systemd,
  jq,
  libsecret,
  libnotify,
}:

{
  package,
  # The program in bin/ to gate.
  exe ? lib.getName package,
  # The `application` attribute of the app's "… Safe Storage" keyring item.
  application,
}:

let
  gate = writeShellScript "${exe}-keyring-gate" ''
    set -o pipefail
    attrs=(xdg:schema chrome_libsecret_os_crypt_password_v2 application ${lib.escapeShellArg application})

    # Prints "<unlocked> <locked>": how many matching items are in each state.
    # The daemon sometimes answers a call with a spurious "not implemented",
    # so a failed search gets a few more tries.
    count() {
      for try in 1 2 3 4 5; do
        ${systemd}/bin/busctl --user --json=short call org.freedesktop.secrets \
          /org/freedesktop/secrets org.freedesktop.Secret.Service SearchItems \
          'a{ss}' 2 "''${attrs[@]}" 2>/dev/null |
          ${jq}/bin/jq -r '"\(.data[0] | length) \(.data[1] | length)"' &&
          return
        sleep 0.2
      done
      return 1
    }

    refuse() {
      echo "${exe}: $1" >&2
      ${libnotify}/bin/notify-send --app-name=${lib.escapeShellArg application} \
        --icon=dialog-password "${application} not started" "$1"
      exit 1
    }

    counts=$(count) || refuse "The keyring (Secret Service) isn't reachable."
    read -r unlocked locked <<<"$counts"

    if [ "$unlocked" -eq 0 ] && [ "$locked" -gt 0 ]; then
      # A lookup asks GNOME to unlock the item's keyring.
      ${libsecret}/bin/secret-tool lookup "''${attrs[@]}" >/dev/null 2>&1
      counts=$(count) || refuse "The keyring (Secret Service) isn't reachable."
      read -r unlocked locked <<<"$counts"
      [ "$unlocked" -gt 0 ] ||
        refuse "The keyring is still locked. Unlock it (e.g. start ${exe} again and enter your password) — starting now would replace its stored password."
    fi

    exec ${package}/bin/${exe} "$@"
  '';
in
symlinkJoin {
  name = "${lib.getName package}-keyring-gated-${lib.getVersion package}";
  paths = [ package ];
  inherit (package) meta;
  postBuild = ''
    rm "$out/bin/${exe}"
    ln -s ${gate} "$out/bin/${exe}"

    # Desktop entries that call the program by its store path would bypass
    # the gate.
    for f in "$out"/share/applications/*.desktop; do
      [ -e "$f" ] || continue
      target=$(readlink -f "$f")
      rm "$f"
      sed "s#${package}/bin/${exe}#$out/bin/${exe}#g" "$target" > "$f"
    done
  '';
}
