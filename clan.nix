{ inputs, ... }:
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
    gondor = {
      deploy.targetHost = "localhost";
      tags = [ "client" ];
    };
  };

  # Docs: See https://docs.clan.lol/reference/clanServices
  inventory.instances = {

    # Docs: https://docs.clan.lol/reference/clanServices/admin/
    # Admin service for managing machines
    # This service adds a root password and SSH access.
    sshd = {
      roles.server.tags.server = { };
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

    # root-password = {
    #   module = {
    #     name = "users";
    #     input = "clan-core";
    #   };
    #   roles.default.tags.all = { };
    #   roles.default.settings = {
    #     user = "root";
    #   };
    # };

    # https://docs.clan.lol/services/official/borgbackup/
    borgbackup = {
      module = {
        name = "borgbackup";
        input = "clan-core";
      };
      roles.client.machines."formenos".settings = {
        destinations."storagebox" = {
          repo = "u366465-sub5@u366465-sub5.your-storagebox.de:/./borgbackup";
          rsh = "ssh -p 23 -oStrictHostKeyChecking=accept-new -i /run/secrets/vars/borgbackup/borgbackup.ssh";
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
    gondor =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [
          ./machines/gondor/hardware.nix
          inputs.home-manager.nixosModules.home-manager
          inputs.agenix.nixosModules.default
        ];

        # Allow unfree packages (obsidian, discord, etc.)
        nixpkgs.config.allowUnfree = true;

        # Add overlays for agenix CLI and alles
        nixpkgs.overlays = [
          inputs.agenix.overlays.default
          (final: prev: {
            alles = inputs.alles.packages.${final.system}.default;
          })
        ];

        # Home Manager configuration
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users."beat" = import ./home/home.nix;
        home-manager.extraSpecialArgs = { inherit inputs; };

        networking.hostName = "gondor";
        clan.core.networking.targetHost = "localhost";

        # Bootloader
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;
        boot.kernelPackages = pkgs.linuxPackages_latest;
        boot.kernelParams = [
          # router can't do ipv6 at home
          "ipv6.disable=1"
          # https://www.reddit.com/r/framework/comments/1goh7hc/anyone_else_get_this_screen_flickering_issue/
          "amdgpu.dcdebugmask=0x410"
        ];

        # Networking
        networking.networkmanager.enable = true;

        # Bluetooth
        hardware.bluetooth.enable = true;

        # Timezone and locale
        time.timeZone = "Europe/Berlin";
        i18n.defaultLocale = "en_US.UTF-8";
        i18n.extraLocaleSettings = {
          LC_ADDRESS = "de_DE.UTF-8";
          LC_IDENTIFICATION = "de_DE.UTF-8";
          LC_MEASUREMENT = "de_DE.UTF-8";
          LC_MONETARY = "de_DE.UTF-8";
          LC_NAME = "de_DE.UTF-8";
          LC_NUMERIC = "de_DE.UTF-8";
          LC_PAPER = "de_DE.UTF-8";
          LC_TELEPHONE = "de_DE.UTF-8";
          LC_TIME = "de_DE.UTF-8";
        };

        # dbus
        services.dbus.implementation = "broker";

        # X11 and GNOME
        services.xserver.enable = true;
        services.displayManager.gdm.enable = true;
        services.desktopManager.gnome = {
          enable = true;
          extraGSettingsOverrides = ''
            [org.gnome.mutter.keybindings]
            switch-monitor=['<Shift><Super>p', 'XF86Display']
          '';
        };

        # Keyboard
        services.xserver.xkb = {
          layout = "us,de";
          variant = "";
        };

        # Sound
        security.rtkit.enable = true;
        services.pulseaudio.enable = false;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        # User
        programs.fish.enable = true;
        users.users.beat = {
          isNormalUser = true;
          description = "Beat Hagenlocher";
          extraGroups = [
            "networkmanager"
            "wheel"
            "docker"
            "dialout"
            "tty"
          ];
          shell = pkgs.fish;
        };

        # Nix settings
        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          trusted-users = [
            "root"
            "beat"
          ];
        };
        nix.gc = {
          automatic = true;
          dates = "monthly";
          options = "--delete-older-than 90d";
        };

        # Docker
        virtualisation.docker.enable = true;
        virtualisation.docker.daemon.settings = {
          default-address-pools = [
            {
              base = "172.30.0.0/16";
              size = 24;
            }
          ];
        };

        # Services
        services.fwupd.enable = true;
        services.printing.enable = true;
        services.upower.percentageLow = 30;
        services.upower.percentageCritical = 15;

        # Fonts
        fonts.packages = with pkgs; [
          nerd-fonts.fira-code
          nerd-fonts.droid-sans-mono
        ];

        # Packages
        environment.systemPackages = with pkgs; [
          git
        ];

        environment.gnome.excludePackages = with pkgs; [
          gnome-tour
          gedit
          cheese
          gnome-music
          epiphany
          geary
          gnome-characters
          tali
          iagno
          hitori
          atomix
          yelp
          gnome-contacts
          gnome-initial-setup
        ];

        programs.dconf.enable = true;

        system.stateVersion = "23.05";
      };

    formenos =
      { _config, pkgs, ... }:
      {
        imports = [
          ./modules/kanidm.nix
          ./modules/kanidm-vars.nix
        ];
        environment.systemPackages = with pkgs; [
          git
          kanidm_1_8
        ];

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
          virtualHosts."paperless.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:28981
            '';
          };
          # virtualHosts."finances.hagenlocher.me" = {
          #   extraConfig = ''
          #     reverse_proxy 127.0.0.1:5006
          #   '';
          # };
          # Automerge Todo App
          virtualHosts."todos.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:3000
            '';
          };
        };

        # https://docs.clan.lol/guides/backups/backup-intro/
        # clan.core.state.actual = {
        #   folders = [
        #     "/var/lib/actual"
        #   ];
        # };
        # https://search.nixos.org/options?channel=unstable&query=services.actual
        # services.actual = {
        #   enable = true;
        #   settings = {
        #     port = 5006;
        #   };
        # };

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
