# Role `scheduler` (orthanc): the nix-builds daemon. A GitHub App webhook
# (and a poll every pollInterval) tells it about new commits of installed
# repos; it evaluates their buildJobs, asks R2 what is missing, and builds
# that on aule, starting aule first if needed. See ./README.md.
{
  settings,
  builderName,
  hostKeyFile,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generators = config.clan.core.vars.generators;
  cache = config.nixBuilds.cache;
  stateDir = "/var/lib/nix-builds";
  port = 8470;

  package = pkgs.callPackage ./scheduler/package.nix { };

  hostKeyReady = builtins.pathExists hostKeyFile;
  appId = generators.nix-builds-github.files.app-id;
  ready = hostKeyReady && appId.exists && cache.ready;
  # The host key lives in the snapshot, so every aule has the same one;
  # ssh checks it under the alias `aule` (HostKeyAlias), not the new IP.
  knownHosts = pkgs.writeText "aule-known-hosts" (
    lib.optionalString hostKeyReady "aule ${lib.fileContents hostKeyFile}\n"
  );

  configFile = pkgs.writeText "nix-builds.json" (
    builtins.toJSON {
      inherit stateDir;
      listen = "127.0.0.1:${toString port}";
      system = "x86_64-linux";
      inherit (settings) tagPattern pollInterval;
      github = {
        appId = appId.value;
        privateKeyFile = generators.nix-builds-github.files.private-key.path;
        webhookSecretFile = generators.nix-builds-github.files.webhook-secret.path;
      };
      hetzner = {
        tokenFile = generators.hcloud-token.files.token.path;
        name = builderName;
        inherit (settings.hetzner) types locations;
      };
      builder = {
        user = "nix-ssh";
        sshKeyFile = generators.nix-builds-ssh.files.id_ed25519.path;
        knownHostsFile = knownHosts;
        bootTimeout = 600;
      };
      cache = {
        store = cache.store "nix-cache-read";
        credentialsFile = generators.nix-cache-read.files.credentials.path;
      };
      ntfy = {
        url = "https://ntfy.sh";
        environmentFile =
          if settings.ntfyGenerator == null then
            null
          else
            generators.${settings.ntfyGenerator}.files.env_file.path;
      };
    }
  );

  # The CLI for operators: `sudo -u nix-builds nix-builds status`.
  cli = pkgs.writeShellScriptBin "nix-builds" ''
    exec ${lib.getExe package} --config ${configFile} "$@"
  '';

  readable = {
    owner = "nix-builds";
    group = "nix-builds";
  };
in
{
  imports = [
    ./builder-vars.nix
    ./client.nix
  ];

  clan.core.vars.generators = {
    nix-builds-ssh.files.id_ed25519 = readable // {
      deploy = true;
    };
    hcloud-token.files.token = readable;
    nix-cache-read.files.credentials.group = "nix-builds";
    nix-cache-read.files.credentials.mode = "0440";

    # The GitHub App (README.md: "Create the GitHub App"). The webhook
    # secret is generated here and pasted into the App's settings.
    nix-builds-github = {
      # Not secret: the App's settings page shows it.
      files.app-id.secret = false;
      files.private-key = readable;
      files.webhook-secret = readable;
      prompts.app-id = {
        type = "line";
        description = "GitHub App ID (the App's settings page, About)";
      };
      prompts.private-key = {
        type = "multiline-hidden";
        description = "GitHub App private key (the .pem GitHub downloads)";
      };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        tr -d '[:space:]' < "$prompts/app-id" > "$out/app-id"
        cp "$prompts/private-key" "$out/private-key"
        openssl rand -hex 32 | tr -d '\n' > "$out/webhook-secret"
      '';
    };
  };

  warnings = lib.optional (!ready) ''
    nix-builds: the scheduler is off until aule's host key, the GitHub App
    ID and the cache vars exist. Run the `clan vars generate` steps in
    clanServices/nix-builds/README.md.
  '';

  users.users.nix-builds = {
    isSystemUser = true;
    group = "nix-builds";
    home = stateDir;
  };
  users.groups.nix-builds = { };

  environment.systemPackages = lib.optional ready cli;

  systemd.services.nix-builds = lib.mkIf ready {
    description = "Build registered repos' buildJobs on aule";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.nix.package
      pkgs.openssh
      pkgs.git
    ];
    environment.HOME = stateDir;
    serviceConfig = {
      ExecStart = "${lib.getExe package} --config ${configFile} serve";
      User = "nix-builds";
      Group = "nix-builds";
      StateDirectory = "nix-builds";
      Restart = "always";
      RestartSec = 10;
      # Evaluation runs here on a 4 GB host with live services: cap it
      # like the updaters, and let the services win CPU and IO.
      MemoryHigh = "1200M";
      MemoryMax = "1500M";
      CPUWeight = 20;
      IOWeight = 20;
      Nice = 10;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  services.caddy = {
    enable = true;
    # Only the webhook and the health check; the queue is not public (it
    # would list private repo names).
    virtualHosts.${settings.domain}.extraConfig = ''
      @hook path /webhook /healthz
      handle @hook {
        reverse_proxy 127.0.0.1:${toString port}
      }
      handle {
        respond 404
      }
    '';
  };
}
