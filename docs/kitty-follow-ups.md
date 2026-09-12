# Kitty follow-up

- `home/programs/kitty.nix` maps `alt+shift+right` to `next_tab_forward`.
  Kitty 0.48.2 defines `move_tab_forward`, but no `next_tab_forward` action.
  This predates the three-pane workspace shortcut and needs a separate fix.
