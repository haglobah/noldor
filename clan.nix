{ inputs, lib, ... }:
let
  # Enable all three hosts together after following docs/todo-home-backup-testing.md.
  todoHomeBackupEnabled = false;
in
{
  # Ensure this is unique among all clans you want to use.
  meta.name = "noldor";
  meta.domain = "noldor";
  meta.description = "My homelab clan";

  inventory.machines = {
    # Define machines here.
    formenos = {
      deploy.targetHost = "root@49.12.12.164";
      tags = [ "server" ];
    };
    orthanc = {
      # Port 443 goes through sslh, which passes SSH through to sshd.
      # Port 22 is blocked on school networks (see home/modules/school-networks.nix).
      deploy.targetHost = "root@91.99.217.220:443";
      tags = [ "client" ];
    };
    # hotlustre at flow.humane.tools, its agent and Beat's repo clones.
    # Hetzner CX43 in hel1, default project (not aule's: aule's token can
    # delete every server in its project). sslh on 443 like orthanc.
    cirdan = {
      deploy.targetHost = "root@2.29.126.128:443";
      tags = [ "server" ];
    };
    gondor = {
      deploy.targetHost = "root@127.0.0.1";
      tags = [ "client" ];
    };
    # On-demand Hetzner build machine (clanServices/nix-builds). `aule` is
    # an ssh alias on gondor that `nix-builder up` points at the current IP.
    # Not "server": instances for long-lived servers should skip it.
    aule = {
      deploy.targetHost = "root@aule";
      tags = [ "builder" ];
    };
  };

  modules."@beat/nix-builds" = import ./clanServices/nix-builds;

  # Docs: See https://docs.clan.lol/reference/clanServices
  inventory.instances = {

    # Private R2 binary cache and on-demand builds of the GitHub App's repos
    # (clanServices/nix-builds/README.md).
    nix-builds = {
      module = {
        name = "@beat/nix-builds";
        input = "self";
      };
      roles.client.tags.all = { };
      roles.builder.machines.aule = { };
      roles.scheduler.machines.orthanc.settings = {
        domain = "builds.hagenlocher.me";
        ntfyGenerator = "updater-alerts";
      };
    };

    openclaw = {
      module = {
        name = "users";
        input = "clan-core";
      };
      roles.default = {
        machines.orthanc = { };
        settings = {
          user = "openclaw";
          prompt = false;
          share = true;
        };
      };
    };

    # Plain NixOS modules for every machine.
    common = {
      module = {
        name = "importer";
        input = "clan-core";
      };
      roles.default.tags.all = { };
      roles.default.extraModules = [ ./modules/resolved.nix ];
    };

    # Docs: https://docs.clan.lol/reference/clanServices/admin/
    # Admin service for managing machines
    # This service adds a root password and SSH access.
    sshd = {
      roles.server.tags.all = { };
      roles.server.settings = {
        authorizedKeys = {
          # Insert the public key that you want to use for SSH access.
          # All keys will have ssh access to all machines ("tags.all" means 'all machines').
          # Alternatively set 'users.users.root.openssh.authorizedKeys.keys' in each machine
          "beat" =
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILD4jhHznn3K7uZGhNTu3En3vDyiLmbColfok2Qm/MKS beat@gondor";
        };
      };
    };

    # monitoring = {
    #   module = {
    #     name = "monitoring";
    #     input = "clan-core";
    #   };

    #   roles = {
    #     client = {
    #       tags = [ "all" ];
    #       settings.useSSL = true;
    #     };

    #     server.machines."formenos".settings = {
    #       grafana.enable = true;
    #       host = "monitoring.hagenlocher.me";
    #       nginx.defaultHTTPListenPort = 8080;
    #       nginx.defaultSSLListenPort = 9443;
    #     };
    #   };
    # };

    root-password = {
      module = {
        name = "users";
        input = "clan-core";
      };
      roles.default.machines.orthanc = { };
      roles.default.machines.formenos = { };
      roles.default.machines.cirdan = { };
      roles.default.settings = {
        user = "root";
        prompt = false;
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
          repo = "u366465-sub5@u366465-sub5.your-storagebox.de:/./borgbackup/formenos";
          rsh = "ssh -p 23 -oStrictHostKeyChecking=accept-new -i /run/secrets/vars/borgbackup/borgbackup.ssh";
        };
      };
      roles.client.machines."orthanc".settings = {
        destinations."storagebox" = {
          repo = "u366465-sub5@u366465-sub5.your-storagebox.de:/./borgbackup/orthanc";
          rsh = "ssh -p 23 -oStrictHostKeyChecking=accept-new -i /run/secrets/vars/borgbackup/borgbackup.ssh";
        };
      };
    };
    # Docs: https://docs.clan.lol/reference/clanServices/zerotier/
    # The lines below will define a zerotier network and add all machines as 'peer' to it.
    # !!! Manual steps required:
    #   - Define a controller machine for the zerotier network.
    #   - Deploy the controller machine first to initialize the network.
    # zerotier = {
    #   # Replace with the name (string) of your machine that you will use as zerotier-controller
    #   # See: https://docs.zerotier.com/controller/
    #   # Deploy this machine first to create the network secrets
    #   roles.controller.machines."formenos" = { };
    #   # Peers of the network
    #   # tags.all means 'all machines' will joined
    #   roles.peer.tags.all = { };
    # };

    # Docs: https://docs.clan.lol/reference/clanServices/tor/
    # Tor network provides secure, anonymous connections to your machines
    # All machines will be accessible via Tor as a fallback connection method
    tor = {
      roles.server.tags.nixos = { };
    };
  };

  # Additional NixOS configuration can be added here.
  # machines/<name>/configuration.nix will be automatically imported.
  # See: https://docs.clan.lol/guides/more-machines/#automatic-registration
  machines = {
    gondor = {
      imports = [
        (import ./machines/gondor/config.nix { inherit inputs; })
      ]
      ++ lib.optionals todoHomeBackupEnabled [
        (import ./modules/todo-home-backup-runner.nix { inherit inputs; })
      ];
      _module.args = { inherit inputs; };
    };
    orthanc =
      { _config, pkgs, ... }:
      {
        _module.args = { inherit inputs; };
        imports = [
          inputs.home-manager.nixosModules.home-manager

          inputs.ht.nixosModules.default
          ./modules/todo-home.nix
          inputs.ht.nixosModules.mail
          ./modules/humane-mail.nix
          inputs.pushout.nixosModules.notes
          ./modules/pushout-notes.nix
          ./modules/agents-container.nix
          inputs.media-inbox.nixosModules.worker
          ./modules/links-worker.nix
          ./modules/updater-alerts.nix

          # inputs.colab.nixosModules.default
          # ./modules/colab.nix

          ./modules/sslh.nix
          ./modules/catppuccin-cache.nix
          ./modules/metrics-shipper.nix
          ./modules/server-housekeeping.nix
        ]
        ++ lib.optionals todoHomeBackupEnabled [ ./modules/todo-home-backup-source.nix ];

        environment.systemPackages = with pkgs; [
          git
          # needed for xterm-kitty being available
          kitty.terminfo
        ];

        networking.firewall = {
          allowedTCPPorts = [
            80
            443
          ];
        };

        # Home Manager configuration
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs; };
        home-manager.users = {
          "root" = {
            imports = [
              inputs.catppuccin.homeModules.catppuccin
              ./home/programs/fish.nix
              ./home/programs/shell-utils.nix
              ./home/programs/starship.nix
            ];
            catppuccin = {
              enable = true;
              # Explicit to match enable; silences the upcoming-autoEnable warning
              autoEnable = true;
              flavor = "macchiato";
              starship.enable = true;
              fzf.enable = true;
              bat.enable = true;
            };
            home.stateVersion = "22.11";
            home.username = "root";
            home.homeDirectory = "/root";
          };
          # "openclaw" = {
          #   imports = [
          #     inputs.nix-openclaw.homeManagerModules.openclaw
          #     ./home/modules/openclaw.nix
          #   ];
          #   home.stateVersion = "22.11";
          #   home.username = "openclaw";
          #   home.homeDirectory = "/home/openclaw";
          # };
        };
      };
    cirdan =
      { pkgs, lib, ... }:
      {
        _module.args = { inherit inputs; };
        imports = [
          inputs.home-manager.nixosModules.home-manager
          ./modules/sslh.nix
          ./modules/metrics-shipper.nix
          ./modules/server-housekeeping.nix
          inputs.hotlustre.nixosModules.default
          ./modules/flow.nix
        ];

        environment.systemPackages = with pkgs; [
          git
          # needed for xterm-kitty being available
          kitty.terminfo
        ];

        hardware.graphics.enable = lib.mkForce false;

        # Builds and Claude processes spike memory; compressed in-RAM swap
        # absorbs them, as on formenos.
        zramSwap = {
          enable = true;
          memoryPercent = 50;
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs; };
        home-manager.users."root" = {
          imports = [
            ./home/programs/fish.nix
            ./home/programs/shell-utils.nix
            ./home/programs/starship.nix
          ];
          programs.broot.enable = lib.mkForce false;
          home.stateVersion = "22.11";
          home.username = "root";
          home.homeDirectory = "/root";
        };
      };
    formenos =
      {
        _config,
        pkgs,
        lib,
        ...
      }:
      {
        _module.args = { inherit inputs; };
        imports = [
          inputs.home-manager.nixosModules.home-manager
          ./modules/kanidm.nix
          ./modules/kanidm-vars.nix
          ./modules/paperless.nix
          ./modules/monitoring.nix
          ./modules/metrics.nix
          ./modules/server-housekeeping.nix
          ./modules/immich.nix
          ./modules/storagebox-secret.nix
          ./modules/audiobookshelf.nix
          # Disabled 2026-08-18 to save ~950 MiB (code-server + elixir toolchain)
          # ./modules/code-server.nix
          ./modules/sslh.nix
          ./modules/media-inbox-notify.nix
          inputs.notable.nixosModules.default
          ./modules/notable.nix
          inputs.notes.nixosModules.default
          ./modules/notes.nix

          # Only here until the grafana service gets fixed
          # ./modules/grafana-secret.nix
        ]
        ++ lib.optionals todoHomeBackupEnabled [ ./modules/todo-home-backup-watchdog.nix ];
        environment.systemPackages = with pkgs; [
          git
          kanidm_1_11
          # needed for xterm-kitty being available
          kitty.terminfo
        ];

        # Headless VPS: facter detected a virtual GPU and enabled mesa,
        # dragging llvm-lib into the closure (~800 MiB)
        hardware.graphics.enable = lib.mkForce false;

        # Don't pin the 200 MiB nixpkgs source into the system closure via
        # the flake registry; `nix shell nixpkgs#...` will fetch it instead
        nixpkgs.flake.setNixPath = false;
        nixpkgs.flake.setFlakeRegistry = false;

        # Home Manager configuration
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users."root" = {
          imports = [
            ./home/programs/fish.nix
            ./home/programs/shell-utils.nix
            ./home/programs/starship.nix
          ];
          # broot leaks its source tree into the runtime closure — not
          # worth it on a server
          programs.broot.enable = lib.mkForce false;
          home.stateVersion = "22.11";
          home.username = "root";
          home.homeDirectory = "/root";
        };
        home-manager.extraSpecialArgs = { inherit inputs; };

        # 4 GB box with no swap: memory spikes OOM-killed nix eval and could
        # just as well hit postgres. Compressed in-RAM swap absorbs them.
        zramSwap = {
          enable = true;
          memoryPercent = 100;
        };

        networking.firewall = {
          allowedTCPPorts = [
            80
            443
          ];
          allowedUDPPorts = [
            80
            443
          ];
        };

        services.caddy = {
          enable = true;
          # Automerge Todo App
          # virtualHosts."todos.hagenlocher.me" = {
          #   extraConfig = ''
          #     reverse_proxy 127.0.0.1:3000
          #   '';
          # };
          # virtualHosts."monitoring.hagenlocher.me" = {
          #   extraConfig = ''
          #     reverse_proxy 127.0.0.1:8080
          #   '';
          # };
        };
      };
  };
}
