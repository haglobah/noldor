# NOTE: This file is very consciously _not_ named configuration.nix, as otherwise
# clan auto-imports it, which breaks because of my dependence on inputs.
# (Same for `./hardware.nix`, which could/should be called `hardware-configuration.nix`)
{ inputs, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./studio-display-watchdog.nix
    ../../modules/storagebox-secret.nix
    ../../modules/storagebox-share.nix
    ../../modules/nix-access-tokens.nix
    # ../../modules/ollama.nix
    ../../modules/catppuccin-cache.nix
    ../../modules/nix-builder-operator.nix
    ../../modules/gnome.nix
    ../../modules/protonvpn.nix
    ../../modules/airplay-receiver.nix
    inputs.home-manager.nixosModules.home-manager
    # Puts `iets` on PATH; iets.classic below routes nix, nix-build,
    # nix-shell and nixos-rebuild through it.
    inputs.iets.nixosModules.default
    # inputs.orca.nixosModules.default
  ];

  # Allow unfree packages (obsidian, discord, etc.)
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.agenix.overlays.default
    (final: prev: {
      alles = inputs.alles.packages.${final.stdenv.hostPlatform.system}.default;
    })
  ];

  # Home Manager configuration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users."beat" = import ../../home/home.nix;

  home-manager.extraSpecialArgs = { inherit inputs; };

  networking.hostName = "gondor";
  clan.core.networking.targetHost = "localhost";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Scripted initrd is deprecated, removal scheduled for NixOS 26.11
  boot.initrd.systemd.enable = true;
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    # router can't do ipv6 at home
    # but enable it again for zerotier
    # "ipv6.disable=1"
    # 0x410 disables PSR and Panel Replay against eDP flicker:
    # https://www.reddit.com/r/framework/comments/1goh7hc/anyone_else_get_this_screen_flickering_issue/
    # 0x4 disables DSC (experiment): the Studio Display ran 5K@60 at 10 bpc
    # with DSC and kept dropping its DP link; 8 bpc fits HBR3 x4 uncompressed.
    "amdgpu.dcdebugmask=0x414"
  ];

  # Networking
  networking.networkmanager.enable = true;

  # The school FortiGate MITMs TCP 443 but can't inspect QUIC; reject outbound
  # UDP 443 on that SSID so browsers fall back to TCP immediately.
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeText "quic-blocker" ''
        #!/bin/sh
        NFT=${pkgs.nftables}/bin/nft
        SSID="DSA-Kursleiter"

        case "$2" in
          up)
            [ "$CONNECTION_ID" = "$SSID" ] || exit 0
            $NFT destroy table inet block-quic
            $NFT add table inet block-quic
            $NFT add chain inet block-quic out '{ type filter hook output priority 0; policy accept; }'
            $NFT add rule inet block-quic out udp dport 443 reject
            ;;
          down)
            [ "$CONNECTION_ID" = "$SSID" ] || exit 0
            $NFT destroy table inet block-quic
            ;;
        esac
      '';
    }
  ];

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Timezone and Locale
  time.timeZone = null; # so that I can set it imperatively from GNOME
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
  # gdm and gnome.enable come from modules/gnome.nix
  services.desktopManager.gnome = {
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

  # Swap caps lock and esc on the internal keyboard only. keyd works at the
  # evdev level and matches by USB id, so external keyboards are untouched.
  # The Framework 16 keyboard modules are swappable; a different module has a
  # different product id and needs its own entry in `ids`.
  services.keyd = {
    enable = true;
    keyboards.framework-internal = {
      ids = [ "32ac:0018" ]; # Framework Laptop 16 Keyboard Module - ISO
      settings.main = {
        capslock = "esc";
        esc = "capslock";
      };
    };
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
      "pipe-operators"
    ];
    trusted-users = [
      "root"
      "beat"
    ];
  };
  # Age-only GC can leave zero rollback targets after a quiet week.
  # nh clean keeps the 3 newest generations regardless of age, plus
  # anything younger than 7d. It also drops direnv gcroots older than
  # 7d (stale .direnv/flake-inputs pinned ~1100 roots) and hard-links
  # duplicate store paths afterwards.
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 3 --keep-since 7d --optimise";
    };
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
  # Goodix 27c6:609c reader. fprintd turns on fprintAuth for every PAM service;
  # keep sudo password-only so a touch alone never grants root.
  services.fprintd.enable = true;
  security.pam.services.sudo.fprintAuth = false;
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
    asdbctl
  ];

  # Apple Studio Display brightness: asdbctl ships a hidraw rule with
  # TAG+="uaccess", so the seated user gets an ACL on /dev/hidraw* for
  # 05ac:1114/1116/1118. Without it the nodes are root-only (0600).
  services.udev.packages = [ pkgs.asdbctl ];
  # Loads i2c-dev and grants the local desktop user access for ddcutil.
  hardware.i2c.enable = true;
  # Keep the USB4 path awake: the USB4 host interfaces, their PCIe tunnel
  # ports and the Thunderbolt routers. Runtime suspend on this path drops
  # the whole Studio Display link now and then; it does not stop the
  # display's own DP drops (see ./studio-display-watchdog.nix).
  services.udev.extraRules = ''
    # bind too: the thunderbolt driver re-enables runtime PM when it (re)probes,
    # which follows add at boot and every rebind by studio-display-watchdog.
    ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{class}=="0x0c0340", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x14ef", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="thunderbolt", ENV{DEVTYPE}=="thunderbolt_device", ATTR{power/control}="on"
  '';

  # Tailscale
  services.tailscale = {
    enable = true;
  };

  environment.gnome.excludePackages = with pkgs; [
    nautilus
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

  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  programs.dconf.enable = true;

  programs.nix-ld.enable = true;

  # iets answers to the classic Nix names and falls back to the real nix
  # for what it doesn't implement. It sets nix.package, so don't set that here.
  iets.classic.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  programs.ausweisapp.enable = true;
  programs.ausweisapp.openFirewall = true;

  system.stateVersion = "23.05";
}
