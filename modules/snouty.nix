# Antithesis' CLI for the antithesis-* skills of Flow's agent
# (./flow.nix, ./flow-gondor.nix). nixpkgs' snouty 0.9.1 links rusqlite
# against the system sqlite (-lsqlite3) without having it as a build
# input, so the link fails; drop this once nixpkgs adds it.
{
  nixpkgs.overlays = [
    (final: prev: {
      snouty = prev.snouty.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.sqlite ];
      });
    })
  ];
}
