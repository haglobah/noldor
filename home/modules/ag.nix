{ inputs, config, ... }:
{
  imports = [
    inputs.nix-starter-kit.homeModules.timetracking
    inputs.nix-starter-kit.homeModules.ldap
    inputs.nix-starter-kit.homeModules.khard
  ];
  active-group = {
    ldap = {
      userName = "hagenlocher";
      fullName = "Beat Hagenlocher";
      email = "beat.hagenlocher@active-group.de";
      phoneNumber = "+49 7071 70896 61";
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
