{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    # Majutsu (Emacs frontend, see ~/.config/doom/packages/majutsu.el) needs jj >= 0.41.
    programs.jujutsu = {
      enable = true;
      settings = {
        user.email = "bah@posteo.de";
        user.name = "Beat Hagenlocher";
        ui.default-command = "log";
        # Move the nearest bookmark up to the last non-empty change before pushing.
        aliases.tug = [
          "bookmark"
          "move"
          "--from"
          "heads(::@- & bookmarks())"
          "--to"
          "@-"
        ];
      };
    };
  };
}
