{
  config,
  pkgs,
  inputs,
  ...
}:
let
  stateDir = "/var/lib/todo-home";
  envFiles = [
    config.clan.core.vars.generators.todo-home-better-auth.files.env_file.path
    config.clan.core.vars.generators.todo-home-resend.files.env_file.path
    config.clan.core.vars.generators.todo-home-creem-api.files.env_file.path
    config.clan.core.vars.generators.todo-home-creem-webhook.files.env_file.path
  ];
  sshKey = config.clan.core.vars.generators.openssh.files."ssh.id_ed25519".path;
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
  services.todo-home.prod = {
    enable = true;
    domain = "todos.humane.tools";
    frontend = inputs.todo-home.packages.x86_64-linux.frontend-deploy;
    backend = inputs.todo-home.packages.x86_64-linux.backend;
    dataDir = stateDir;
    envFiles = envFiles;
    authPort = 3001;
    syncPort = 3030;

    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/todo-home.git";
      strategy = "tag";
      tagPattern = "v*";
      # This key is added to github
      sshKeyFile = sshKey;
      # NOTE: This is the derivation the autoupdater tries to build.
      # Optimally, I'd like this to be derived from `services.todo-home.<name>.frontend`,
      # and get rid of the sync server coupling in todo-home/flake.nix
      frontendFlakeOutput = "frontend-deploy";
    };
  };
  services.todo-home.dev = {
    enable = true;
    domain = "dev.todos.humane.tools";
    frontend = inputs.todo-home.packages.x86_64-linux.frontend.override {
      syncServerUrl = "wss://dev.todos.humane.tools/sync";
    };
    backend = inputs.todo-home.packages.x86_64-linux.backend;
    dataDir = stateDir;
    envFiles = envFiles;
    authPort = 3101;
    syncPort = 3130;

    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/todo-home.git";
      branch = "main";
      # This key is added to github
      sshKeyFile = sshKey;
      # NOTE: This is the derivation the autoupdater tries to build.
      # Optimally, I'd like this to be derived from `services.todo-home.<name>.frontend`,
      # and get rid of the sync server coupling in todo-home/flake.nix
      frontendFlakeOutput = "frontend-deploy-dev";
    };
  };
}
