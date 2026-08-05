{ inputs, config, ... }:
{
  imports = [
    inputs.nix-starter-kit.homeModules.timetracking
    inputs.nix-starter-kit.homeModules.ldap
    inputs.nix-starter-kit.homeModules.thunderbird
    inputs.nix-starter-kit.homeModules.khard
  ];
  active-group = {
    ldap = {
      userName = "hagenlocher";
      fullName = "Beat Hagenlocher";
      email = "beat.hagenlocher@active-group.de";
      phoneNumber = "+49 7071 70896 61";
    };
    thunderbird =
      let
        colors = [
          "#ff5d59"
          "#ff9a86"
          "#d2866d"
          "#f76d00"
          "#ffb675"
          "#d28a31"
          "#ff9e00"
          "#ffdb82"
          "#d2ba69"
          "#cea200"
          "#ffdf2d"
          "#aa9e51"
          "#babe00"
          "#c2db8e"
          "#caf771"
          "#a6ff00"
          "#86ae4d"
          "#59be00"
          "#92d75d"
          "#41eb00"
          "#b6f7be"
          "#69ff82"
          "#71b282"
          "#1cba59"
          "#86d2aa"
          "#14df82"
          "#04ffba"
          "#00bea2"
          "#00e3c6"
          "#92fbff"
          "#82d2d7"
          "#61aeb6"
          "#00d7ff"
          "#1caaff"
          "#7dbae3"
          "#aadbff"
          "#8a9ed2"
          "#aebeff"
          "#9a92ff"
          "#ae92d2"
          "#d2b2fb"
          "#ce71fb"
          "#ff24ff"
          "#ffc2ff"
          "#ff7dff"
          "#d279ca"
          "#fb82c6"
          "#ff519e"
          "#db7d96"
          "#ffa2ba"
        ];
      in
      {
        enable = true;
        calendars = {
          enableAGCalendars = true;
          generateColors = (i: n: builtins.elemAt colors i);
          beat = {
            readOnly = false;
            suppressAlarms = false;
          };
          geburtstage.color = "#0000ff";
          regeltermine.color = "#0000ff";

          pr.enable = false;
        };
      };
    timetracking = {
      enable = true;
      timetracking-token = config.age.secrets.timetracking-secret.path;
      arbeitszeiten-token = config.age.secrets.arbeitszeiten-secret.path;
      abrechenbare-zeiten-token = config.age.secrets.abrechenbare-zeiten-secret.path;
    };

    khard = {
      enable = true;
      storagePath = "/home/beat/ag/addresses/vcf";
    };
  };

  accounts.email.accounts = {
    ag = rec {
      address = "beat.hagenlocher@active-group.de";
      realName = "Beat Hagenlocher";
      userName = address;
      passwordCommand = "cat ~/.agpassword";
      imap = {
        host = "mail.active-group.de";
        port = null;
        tls = {
          enable = true;
          useStartTls = true;
        };
      };
      smtp = {
        host = "mail.active-group.de";
        port = null;
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
      mu.enable = true;
      msmtp = {
        enable = true;
        extraConfig = {
          "syslog" = "LOG_USER";
        };
      };
    };
  };
  programs.git = {
    includes = [
      {
        condition = "gitdir:~/ag/";
        contents = {
          user.email = "beat.hagenlocher@active-group.de";
        };
      }
    ];
    settings.url = {
      "https://gitlab.active-group.de" = {
        insteadOf = "ssh://git@gitlab.active-group.de";
      };
      "git@gitlab.active-group.de:ag/" = {
        insteadOf = "ag:";
      };
      "git@github.com:active-group/" = {
        insteadOf = "agh:";
      };
    };
  };

}
