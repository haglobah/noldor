{ config, pkgs, lib, ... }:
let
  instanceCount = 16;

  instances = lib.genList (i: rec {
    name = "coder-${lib.fixedWidthString 2 "0" (toString (i + 1))}";
    port = 4401 + i;
    stateDir = "/var/lib/${name}";
  }) instanceCount;

  codeServerPackage = pkgs.vscode-with-extensions.override {
    vscode = pkgs.code-server;
    vscodeExtensions = with pkgs.vscode-extensions; [
      bbenoist.nix
      dracula-theme.theme-dracula
    ];
  };
in
{
  config = {
    # Create a separate user and group for each instance
    users.users = lib.listToAttrs (map (inst: lib.nameValuePair inst.name {
      isSystemUser = true;
      group = inst.name;
      home = inst.stateDir;
      createHome = true;
      shell = pkgs.bashInteractive;
    }) instances);

    users.groups = lib.listToAttrs (map (inst: lib.nameValuePair inst.name { }) instances);

    # Create a systemd service for each instance
    systemd.services = lib.listToAttrs (map (inst: lib.nameValuePair "code-server-${inst.name}" {
      description = "Code Server (${inst.name})";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ git ];

      serviceConfig = {
        Type = "exec";
        User = inst.name;
        Group = inst.name;
        ExecStart = lib.concatStringsSep " " [
          "${codeServerPackage}/bin/code-server"
          "--bind-addr 127.0.0.1:${toString inst.port}"
          "--auth password"
          "--user-data-dir ${inst.stateDir}/data"
          "--extensions-dir ${inst.stateDir}/extensions"
        ];
        WorkingDirectory = inst.stateDir;
        EnvironmentFile = "${inst.stateDir}/password.env";
        StateDirectory = inst.name;
        Restart = "on-failure";

        # Isolation
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ inst.stateDir ];
      };

      preStart = ''
        if [ ! -f ${inst.stateDir}/password.env ]; then
          PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 16)
          echo "PASSWORD=$PASSWORD" > ${inst.stateDir}/password.env
          chmod 600 ${inst.stateDir}/password.env
          echo "$PASSWORD" > ${inst.stateDir}/password.txt
          chmod 600 ${inst.stateDir}/password.txt
        fi
      '';
    }) instances);

    # Caddy reverse proxy for each instance
    services.caddy = {
      enable = true;
      virtualHosts = lib.listToAttrs (map (inst: lib.nameValuePair "http://${inst.name}.local" {
        extraConfig = ''
          reverse_proxy localhost:${toString inst.port}
        '';
      }) instances);
    };

    # Resolve .local hostnames on this machine
    networking.extraHosts = lib.concatMapStringsSep "\n"
      (inst: "127.0.0.1 ${inst.name}.local") instances;

    # Avahi for mDNS on the local network
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    # Open port 80 for HTTP access on the local network
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
