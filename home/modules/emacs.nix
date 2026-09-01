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
        # doom sync regenerates ~/.config/emacs/.local/env when it
        # exists, snapshotting this process's environment. Doom loads
        # that file at startup and it REPLACES Emacs's PATH, so the
        # PATH here must contain the user session bins (mbsync, mu,
        # ...) or mu4e and friends break until the next `doom env`.
        # Activation runs with a minimal PATH, so list them explicitly.
        if run env PATH="${
          lib.makeBinPath [
            emacsWithPackages
            pkgs.git
          ]
        }:/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH" \
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
