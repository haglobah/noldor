{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = {
    programs.mbsync.enable = true;
    programs.msmtp.enable = true;
    programs.mu.enable = true;
    accounts.email.accounts = {
      posteo = {
        primary = true;
        address = "bah@posteo.de";
        realName = "Beat Hagenlocher";
        # This is the userName used at the server
        userName = "hagenlob@posteo.de";
        passwordCommand = "cat ~/.posteopassword";
        signature = {
          text = ''
            Liebe Grüße
            Beat Hagenlocher
          '';
          showSignature = "append";
        };

        imap = {
          host = "posteo.de";
          port = 993;
          tls.enable = true;
        };
        smtp = {
          host = "posteo.de";
          port = 465;
          tls.enable = true;
        };

        mbsync = {
          enable = true;
          create = "both";
          remove = "both";
          expunge = "both";
          patterns = [
            "*"
            "!Drafts"
            "!Deleted Messages"
          ];
        };
        msmtp.enable = true;
        mu.enable = true;
        thunderbird.enable = true;
      };
    };
  };
}
