{
  config,
  pkgs,
  inputs,
  ...
}:
{
  clan.core.vars.generators = {
    todo-home-env = {
      share = true;
      files = {
        "env_file" = { };
      };
      prompts."resend-api-key" = {
        type = "line";
        description = "The resend api key";
      };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        cat > "$out/env_file" <<here
        RESEND_API_KEY=$(cat $prompts/resend-api-key)
        BETTER_AUTH_SECRET=$(openssl rand -base64 32)
        here
      '';
    };
  };

  services.todo-home = {
    enable = true;
    domain = "todos.humane.tools";
    frontend = inputs.todo-home.packages.x86_64-linux.frontend-deploy;
    backend = inputs.todo-home.packages.x86_64-linux.backend;
    envFile = config.clan.core.vars.generators.todo-home-env.files.env_file.path;
    authPort = 13001;

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
