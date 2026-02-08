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
    inputs.home-manager.nixosModules.home-manager
    inputs.agenix.nixosModules.default

  ];

  # Allow unfree packages (obsidian, discord, etc.)
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.agenix.overlays.default
    (final: prev: {
      alles = inputs.alles.packages.${final.system}.default;
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
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    # router can't do ipv6 at home
    # but enable it again for zerotier
    # "ipv6.disable=1"
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
}
