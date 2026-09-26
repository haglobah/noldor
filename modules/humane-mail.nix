# Humane Mail on orthanc: dev follows ht main, prod follows v* tags, like Todo.
# Module and rollout notes: ht/apps/mail/docs/production.md; the Todo-side
# settings this pairs with live in ./todo-home.nix.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  mailPackages = inputs.ht.packages.x86_64-linux;
  sshKey = config.clan.core.vars.generators.openssh.files."ssh.id_ed25519".path;

  # One generator per instance: dev and prod must not share a credentials key
  # or bridge token. Two files come out of one run so both sides of the Todo
  # bridge hold the same token: `mail_env` is the Mail engine's environment
  # file, `todo_env` joins the matching Todo instance's envFiles.
  #
  # NEVER regenerate an instance whose Mail database holds accounts: a new
  # CREDENTIALS_KEY makes every stored IMAP credential unreadable and the
  # accounts have to be added again. The engine then logs "Unsupported state
  # or unable to authenticate data".
  bridge = origin: {
    share = true;
    files."mail_env" = { };
    files."todo_env" = { };
    prompts."vapid-subject" = {
      type = "line";
      description = "Web push contact for ${origin}, a mailto: address (VAPID_SUBJECT)";
    };
    runtimeInputs = [
      pkgs.openssl
      pkgs.coreutils
    ];
    # The VAPID pair is what `bunx web-push generate-vapid-keys` produces:
    # P-256, private key = the 32 raw bytes at offset 7 of the SEC1 DER,
    # public key = the 65-byte uncompressed point, both base64url unpadded.
    script = ''
      tmp=$(mktemp -d)
      openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/vapid.pem"
      vapid_private=$(openssl ec -in "$tmp/vapid.pem" -outform DER 2>/dev/null \
        | head -c 39 | tail -c 32 | base64 -w0 | tr '+/' '-_' | tr -d '=')
      vapid_public=$(openssl ec -in "$tmp/vapid.pem" -pubout -outform DER 2>/dev/null \
        | tail -c 65 | base64 -w0 | tr '+/' '-_' | tr -d '=')
      rm -rf "$tmp"
      bridge_token=$(openssl rand -hex 32)
      {
        echo "CREDENTIALS_KEY=$(openssl rand -hex 32)"
        echo "MAIL_BRIDGE_TOKEN=$bridge_token"
        echo "VAPID_PUBLIC_KEY=$vapid_public"
        echo "VAPID_PRIVATE_KEY=$vapid_private"
        echo "VAPID_SUBJECT=$(cat "$prompts/vapid-subject")"
      } > "$out/mail_env"
      {
        echo "MAIL_BRIDGE_TOKEN=$bridge_token"
        echo "MAIL_BRIDGE_ORIGIN=${origin}"
      } > "$out/todo_env"
    '';
  };

  common = {
    enable = true;
    frontend = mailPackages.mail-frontend;
    backend = mailPackages.mail-backend;
    autoUpdate = {
      enable = true;
      repo = "git@github.com:haglobah/ht.git";
      # The same deploy key Todo's updaters use; it is registered on GitHub.
      sshKeyFile = sshKey;
    };
  };
in
{
  clan.core.vars.generators = {
    humane-mail-prod = bridge "https://mail.humane.tools";
    humane-mail-dev = bridge "https://dev.mail.humane.tools";
  };

  clan.core.state.humane-mail = {
    folders = [
      config.services.humane-mail.instances.prod.dataDir
      config.services.humane-mail.instances.dev.dataDir
    ];
  };

  services.humane-mail.instances = {
    prod = common // {
      domain = "mail.humane.tools";
      port = 3201;
      # /metrics on 127.0.0.1, scraped by vmagent (./metrics-shipper.nix).
      metricsPort = 3209;
      authServiceUrl = "https://todos.humane.tools";
      environmentFile = config.clan.core.vars.generators.humane-mail-prod.files.mail_env.path;
      autoUpdate = common.autoUpdate // {
        strategy = "tag";
        tagPattern = "v*";
      };
    };
    dev = common // {
      domain = "dev.mail.humane.tools";
      port = 3301;
      metricsPort = 3309;
      authServiceUrl = "https://dev.todos.humane.tools";
      environmentFile = config.clan.core.vars.generators.humane-mail-dev.files.mail_env.path;
      autoUpdate = common.autoUpdate // {
        strategy = "branch";
        branch = "main";
      };
    };
  };
}
