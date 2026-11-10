# hotlustre's notes, synced between its two instances directly: gondor's
# server relays them to cirdan's notes socket (wss://flow.humane.tools/sync)
# instead of to the notes server of humane tools (./pushout-notes.nix), which
# was the only link between the two. cirdan's core lets this shared token
# through to /sync, as a bearer on the WebSocket upgrade, and nowhere else
# (hotlustre's core/main.ts notesPeer; the version's server/plugins/humane.ts
# peerSync dials with it when HOTLUSTRE_NOTES_PEER is set).
#
# Shared, so both machines hold the same generated value. Imported by
# ./flow.nix (cirdan, which accepts it) and ./flow-gondor.nix (which dials).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  vars = config.clan.core.vars.generators;
in
{
  clan.core.vars.generators.flow-notes-peer = {
    share = true;
    files.env.owner = "beat";
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      echo "HOTLUSTRE_NOTES_PEER_TOKEN=$(openssl rand -hex 32)" > "$out/env"
    '';
  };

  # The module's environmentFile holds one file; systemd takes several.
  systemd.services.hotlustre.serviceConfig.EnvironmentFile = lib.mkForce (
    lib.optional (config.services.hotlustre.environmentFile != null) config.services.hotlustre.environmentFile
    ++ [ vars.flow-notes-peer.files.env.path ]
  );
}
