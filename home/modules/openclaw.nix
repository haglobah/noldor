{ config, ... }:
{
  config = {
    age.secrets.gatewaytoken.file = ../orthanc/gatewaytoken.age;
    age.secrets.identityPaths = [
      "/home/beat/.ssh/openclaw"
      "/home/beat/.ssh/id_ed25519"
    ];

    home.sessionVariables = {
      OPENCLAW_GATEWAY_TOKEN = "$(cat ${config.age.secrets.gatewaytoken})";
    };

    programs.openclaw = {
      enable = true;
      documents = ../dotfiles/openclaw;

      config = {
        gateway = {
          mode = "local";
        };
      };
    };
  };
}
