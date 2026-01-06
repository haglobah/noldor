{
  # Ensure this is unique among all clans you want to use.
  meta.name = "noldor";
  meta.tld = "noldor";

  inventory.machines = {
    # Define machines here.
    formenos = {
      deploy.targetHost = "root@49.12.12.164";
      tags = [ ];
    };
  };

  # Docs: See https://docs.clan.lol/reference/clanServices
  inventory.instances = {

    # Docs: https://docs.clan.lol/reference/clanServices/admin/
    # Admin service for managing machines
    # This service adds a root password and SSH access.
    admin = {
      roles.default.tags.all = { };
      roles.default.settings.allowedKeys = {
        # Insert the public key that you want to use for SSH access.
        # All keys will have ssh access to all machines ("tags.all" means 'all machines').
        # Alternatively set 'users.users.root.openssh.authorizedKeys.keys' in each machine
        "beat" =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILD4jhHznn3K7uZGhNTu3En3vDyiLmbColfok2Qm/MKS beat@gondor";
      };
    };

    # https://docs.clan.lol/services/official/borgbackup/
    borgbackup = {
      module = {
        name = "borgbackup";
        input = "clan-core";
      };
      roles.client.machines."formenos".settings = {
        destinations."storagebox" = {
          repo = "u366465-sub5@u366465-sub5.your-storagebox.de:/./borgbackup";
          rsh = ''ssh -p 23 -oStrictHostKeyChecking=accept-new -i /run/secrets/vars/borgbackup/borgbackup.ssh'';
        };
      };
    };
    # Docs: https://docs.clan.lol/reference/clanServices/zerotier/
    # The lines below will define a zerotier network and add all machines as 'peer' to it.
    # !!! Manual steps required:
    #   - Define a controller machine for the zerotier network.
    #   - Deploy the controller machine first to initialize the network.
    zerotier = {
      # Replace with the name (string) of your machine that you will use as zerotier-controller
      # See: https://docs.zerotier.com/controller/
      # Deploy this machine first to create the network secrets
      roles.controller.machines."formenos" = { };
      # Peers of the network
      # tags.all means 'all machines' will joined
      roles.peer.tags.all = { };
    };

    # Docs: https://docs.clan.lol/reference/clanServices/tor/
    # Tor network provides secure, anonymous connections to your machines
    # All machines will be accessible via Tor as a fallback connection method
    tor = {
      roles.server.tags.nixos = { };
    };
  };

  # Additional NixOS configuration can be added here.
  # machines/jon/configuration.nix will be automatically imported.
  # See: https://docs.clan.lol/guides/more-machines/#automatic-registration
  machines = {
    numenor =
      { config, pkgs, agenix, ... }:
      {
      nixpkgs.hostPlatform = "x86_64-linux";
      # inherit system;
      imports = [
        ./modules/configuration.nix
        ./modules/hardware/numenor.nix
        ./modules/numenor.nix
        agenix.nixosModules.default
      ];
    };
    gondor =
      { config, pkgs, agenix, home-manager, inputs, ... }:
      {
      # inherit system pkgs;
      specialArgs = { inherit inputs; };
      imports = [
        ./modules/configuration.nix
        ./modules/hardware/gondor.nix
        ./modules/gondor.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.users."beat" = ./modules/home/home.nix;
          home-manager.extraSpecialArgs = { inherit inputs; };
        }
        agenix.nixosModules.default
      ];
    };
    formenos =
      { _config, pkgs, ... }:
      {
        imports = [
          ./modules/logto-compose.nix
          ./modules/logto-postgres-login.nix
        ];
        environment.systemPackages = [ pkgs.git ];

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        services.caddy = {
          enable = true;
          virtualHosts."paperless.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:28981
            '';
          };
          virtualHosts."finances.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:5006
            '';
          };
          virtualHosts."auth-todos.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:3001
            '';
          };
          virtualHosts."admin-todos.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:3002
            '';
          };
        };

        clan.core.state.todo-home = {
          folders = [
            "/var/lib/containers/volumes/logto_postgres_data"
          ];
        };

        # https://docs.clan.lol/guides/backups/backup-intro/
        clan.core.state.actual = {
          folders = [
            "/var/lib/actual"
          ];
        };
        # https://search.nixos.org/options?channel=unstable&query=services.actual
        services.actual = {
          enable = true;
          settings = {
            port = 5006;
          };
        };

        # https://docs.clan.lol/guides/backups/backup-intro/
        clan.core.state.paperless = {
          folders = [
            "/var/lib/paperless"
          ];
        };
        # https://wiki.nixos.org/wiki/Paperless-ngx
        services.paperless = {
          enable = true;
          consumptionDirIsPublic = true;
          settings = {
            PAPERLESS_CONSUMER_IGNORE_PATTERN = [
              ".DS_STORE/*"
              "desktop.ini"
            ];
            PAPERLESS_OCR_LANGUAGE = "deu+eng";
            PAPERLESS_OCR_USER_ARGS = {
              optimize = 1;
              pdfa_image_compression = "lossless";
            };
            PAPERLESS_URL = "https://paperless.hagenlocher.me";
          };
        };
      };
  };
}
