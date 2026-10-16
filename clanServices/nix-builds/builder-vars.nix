# The Hetzner token, shared by roles `builder` (aule), `scheduler` (orthanc)
# and the operator CLI on gondor (../../modules/nix-builder-operator.nix).
# All three deploy it; only the owner differs, which clan allows.
{ ... }:
{
  clan.core.vars.generators = {
    # Hetzner Cloud API token (Read & Write). The scheduler creates aule,
    # aule deletes itself, gondor refreshes the snapshot.
    hcloud-token = {
      share = true;
      files.token = { };
      prompts.token = {
        type = "hidden";
        description = "Hetzner Cloud API token (project of aule, Read & Write)";
      };
      script = ''tr -d '[:space:]' < "$prompts/token" > "$out/token"'';
    };
  };
}
