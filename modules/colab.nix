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
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        cat > "$out/env_file" <<here
        SECRET_KEY_BASE=$(openssl rand -base64 32)
        DATABASE_USERNAME=colab
        DATABASE_PASSWORD=$(openssl rand -base64 32)
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
