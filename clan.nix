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
  # machines/<name>/configuration.nix will be automatically imported.
  # See: https://docs.clan.lol/guides/more-machines/#automatic-registration
  machines = {
    gondor = import ./machines/gondor/config.nix { inherit inputs; };
    formenos =
      { _config, pkgs, ... }:
      {
        imports = [
          ./modules/kanidm.nix
          ./modules/kanidm-vars.nix
          ./modules/paperless.nix
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
          # Automerge Todo App
          virtualHosts."todos.hagenlocher.me" = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:3000
            '';
          };
        };
      };
  };
}
