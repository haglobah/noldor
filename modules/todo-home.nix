{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  envFiles = [
    config.clan.core.vars.generators.todo-home-better-auth.files.env_file.path
    config.clan.core.vars.generators.todo-home-resend.files.env_file.path
    config.clan.core.vars.generators.todo-home-creem-api.files.env_file.path
    config.clan.core.vars.generators.todo-home-creem-webhook.files.env_file.path
  ];
  sshKey = config.clan.core.vars.generators.openssh.files."ssh.id_ed25519".path;
  # The Mail bridge token and origin, minted per instance in ./humane-mail.nix
  # so both sides of the bridge hold the same token.
  mailBridgeEnv =
    instance: config.clan.core.vars.generators."humane-mail-${instance}".files.todo_env.path;
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

  # Preserve the current test-mode behavior explicitly. Switch production only
  # together with matching live credentials and HT's public product configuration.
  systemd.services.todo-home-prod.environment.CREEM_TEST_MODE = lib.mkDefault "true";
  systemd.services.todo-home-dev.environment.CREEM_TEST_MODE = lib.mkDefault "true";

  clan.core.state.todo-home = {
    folders = [
      config.services.todo-home.prod.dataDir
      config.services.todo-home.dev.dataDir
    ];
  };
  services.todo-home.prod = {
    enable = true;
    domain = "todos.humane.tools";
    frontend = inputs.ht.packages.x86_64-linux.frontend-deploy;
    backend = inputs.ht.packages.x86_64-linux.backend;
    envFiles = envFiles; # ++ [ (mailBridgeEnv "prod") ];
    # Shared sessions with mail.humane.tools (ht/apps/mail/README.md, "Running
    # against a real account"): the parent cookie domain lets a Todo login
    # carry over to Mail; the prefix is new, so every user signs in once more
    # after the first rollout. Mail's origin must be trusted or Better Auth
    # refuses its proxied cookie-bearing requests (sign-out) as "Invalid origin".
    sharedCookieDomain = "humane.tools";
    cookiePrefix = "humane-shared";
    trustedOrigins = [ "https://mail.humane.tools" ];
    authPort = 3001;
    syncPort = 3030;
    # The module turns the boot-time topology split on by default. Prod stays
    # off until the runbook (ht/apps/todos/docs/design/topology-deploy.md: backup,
    # copy, dry run) has been walked for the M3 tag.
    topologyMigrateOnBoot = true;

    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/ht.git";
      strategy = "tag";
      tagPattern = "v*";
      interval = "*:0/1";
      # This key is added to github
      sshKeyFile = sshKey;
      # NOTE: This is the derivation the autoupdater tries to build.
      # Optimally, I'd like this to be derived from `services.todo-home.<name>.frontend`,
      # and get rid of the sync server coupling in ht/flake.nix
      frontendFlakeOutput = "frontend-deploy";
    };
  };
  services.todo-home.dev = {
    enable = true;
    domain = "dev.todos.humane.tools";
    frontend = inputs.ht.packages.x86_64-linux.frontend-deploy-dev;
    backend = inputs.ht.packages.x86_64-linux.backend;
    envFiles = envFiles ++ [ (mailBridgeEnv "dev") ];
    # No parent cookie domain here: every humane.tools subdomain would join
    # the trust boundary, and production cookies must never reach dev. The
    # distinct prefix keeps prod's shared cookies unreadable here regardless.
    # Mail's proxied login still works without shared cookies; only seamless
    # session hand-over between dev.todos and dev.mail is lost.
    cookiePrefix = "humane-dev";
    trustedOrigins = [ "https://dev.mail.humane.tools" ];
    authPort = 3101;
    syncPort = 3130;

    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/ht.git";
      branch = "main";
      interval = "*:0/1";
      # This key is added to github
      sshKeyFile = sshKey;
      # NOTE: This is the derivation the autoupdater tries to build.
      # Optimally, I'd like this to be derived from `services.todo-home.<name>.frontend`,
      # and get rid of the sync server coupling in ht/flake.nix
      frontendFlakeOutput = "frontend-deploy-dev";
    };
  };
}
