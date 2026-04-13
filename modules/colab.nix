{
  config,
  pkgs,
  inputs,
  ...
}:
let
  stateDir = "/var/lib/colab";
in
{
  clan.core.vars.generators = {
    colab-env = {
      share = true;
      files = {
        "env_file" = { };
      };
      prompts."secret-key-base" = {
        type = "line";
        description = "The Phoenix secret key base (generate with: mix phx.gen.secret)";
      };
      prompts."database-username" = {
        type = "line";
        description = "The SurrealDB root username";
      };
      prompts."database-password" = {
        type = "line";
        description = "The SurrealDB root password";
      };
      script = ''
        cat > "$out/env_file" <<here
        SECRET_KEY_BASE=$(cat $prompts/secret-key-base)
        DATABASE_USERNAME=$(cat $prompts/database-username)
        DATABASE_PASSWORD=$(cat $prompts/database-password)
        here
      '';
    };
  };

  clan.core.state.colab = {
    folders = [
      stateDir
    ];
  };

  services.colab = {
    enable = true;
    domain = "zelium.io";
    dataDir = stateDir;
    envFile = config.clan.core.vars.generators.colab-env.files.env_file.path;
    repo = "git@github.com:haglobah/colab.git";
    branch = "noldor-deploy";
    sshKeyFile = config.clan.core.vars.generators.openssh.files."ssh.id_ed25519".path;
    updateInterval = "*:0/1";
  };
}
