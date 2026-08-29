{
  config,
  pkgs,
  lib,
  ...
}:
let
  emacsWithPackages = (pkgs.emacsPackagesFor pkgs.emacs30).emacsWithPackages (epkgs: [
    epkgs.mu4e
  ]);
in
{
  config = {
    home.packages = [ emacsWithPackages ];

    # `doom sync` snapshots absolute /nix/store paths (e.g. the mu4e
    # site-lisp) into its generated init file, so a rebuild that changes
    # the Emacs closure leaves Doom loading stale elisp until the next
    # sync. Re-sync whenever the Emacs store path differs from the
    # recorded one. The comparison is for inequality, not newness, so a
    # rollback re-syncs as well.
    home.activation.doomSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      doomBin="$HOME/.config/emacs/bin/doom"
      stateFile="${config.xdg.stateHome}/doom-sync-emacs-path"
      currentEmacs="${emacsWithPackages}"

      if [ ! -x "$doomBin" ]; then
        warnEcho "doomSync: $doomBin not found or not executable; skipping"
      elif [ "$(cat "$stateFile" 2>/dev/null || true)" != "$currentEmacs" ]; then
        echo "doomSync: Emacs closure changed; running doom sync"
        if run env PATH="${
          lib.makeBinPath [
            emacsWithPackages
            pkgs.git
          ]
        }:$PATH" \
          "$doomBin" sync
        then
          run mkdir -p "$(dirname "$stateFile")"
          run sh -c "printf '%s' '$currentEmacs' > '$stateFile'"
        else
          # Do not record the path on failure: the sync retries on the
          # next activation instead of silently staying stale.
          warnEcho "doomSync: doom sync failed; mu4e may load stale elisp"
          warnEcho "doomSync: run 'doom sync' manually, or re-activate to retry"
        fi
      fi
    '';
  };
}
