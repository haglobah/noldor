{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    programs.git = {
      enable = true;
      ignores = [
        ".envrc"
        ".direnv/"

        ".calva"

        # Emacs
        "*~"
        "\\#*\\#"
        ".\\#*"
        ".dir-locals.el"
      ];
      signing.format = "ssh";
      settings = {
        user.email = "bah@posteo.de";
        user.name = "Beat Hagenlocher";
        color.ui = "auto";
        # Breaks active-timetracking
        # core.sshCommand = "ssh -i ~/.ssh/id_rsa -i ~/.ssh/id_ed25519 2> /dev/null";
        init.defaultBranch = "main";
        checkout.defaultRemote = "origin";
        rerere.enabled = true;
        branch.sort = "-committerdate";
        diff = {
          algorithm = "histogram";
          mnemonicPrefix = true;
          renames = true;
        };
        merge.conflictStyle = "zdiff3";
        fetch = {
          prune = true;
          pruneTags = true;
          all = true;
        };
        url = {
          "https://github.com/" = {
            insteadOf = "gh:";
          };
          "git@github.com:" = {
            insteadOf = "gs:";
          };
          "git@github.com:haglobah/" = {
            insteadOf = "bah:";
          };
          "https://gitlab.com/" = {
            insteadOf = "gl:";
          };
        };
      };
    };
  };
}
