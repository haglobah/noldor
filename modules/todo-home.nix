{
  config,
  pkgs,
  inputs,
  ...
}:
let
  stateDir = "/var/lib/todo-home";
in
{
  clan.core.vars.generators = {
    todo-home-better-auth = {
      share = true;
      files."env_file" = { };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        echo "BETTER_AUTH_SECRET=$(openssl rand -base64 32)" > "$out/env_file"
      '';
    };
    todo-home-resend = {
      share = true;
      files."env_file" = { };
      prompts."resend-api-key" = {
        type = "line";
        description = "The resend api key";
      };
      script = ''
        echo "RESEND_API_KEY=$(cat $prompts/resend-api-key)" > "$out/env_file"
      '';
    };
    todo-home-creem-api = {
      share = true;
      files."env_file" = { };
      prompts."creem-api-key" = {
        type = "line";
        description = "The creem api key";
      };
      script = ''
        echo "CREEM_API_KEY=$(cat $prompts/creem-api-key)" > "$out/env_file"
      '';
    };
    todo-home-creem-webhook = {
      share = true;
      files."env_file" = { };
      prompts."creem-webhook-secret" = {
        type = "line";
        description = "The creem webhook secret";
      };
      script = ''
        echo "CREEM_WEBHOOK_SECRET=$(cat $prompts/creem-webhook-secret)" > "$out/env_file"
      '';
    };
  };

  clan.core.state.todo-home = {
    folders = [
      stateDir
    ];
  };
  services.todo-home = {
    enable = true;
    domain = "todos.humane.tools";
    frontend = inputs.todo-home.packages.x86_64-linux.frontend-deploy;
    backend = inputs.todo-home.packages.x86_64-linux.backend;
    dataDir = stateDir;
    envFiles = [
      config.clan.core.vars.generators.todo-home-better-auth.files.env_file.path
      config.clan.core.vars.generators.todo-home-resend.files.env_file.path
      config.clan.core.vars.generators.todo-home-creem-api.files.env_file.path
      config.clan.core.vars.generators.todo-home-creem-webhook.files.env_file.path
    ];

    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/todo-home.git";
      branch = "main";
      interval = "*:0/1";
      # This key is added to github
      sshKeyFile = config.clan.core.vars.generators.openssh.files."ssh.id_ed25519".path;
      frontendFlakeOutput = "frontend-deploy";
    };
  };
}
