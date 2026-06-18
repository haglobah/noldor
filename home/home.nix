{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    inputs.catppuccin.homeModules.catppuccin
    inputs.agenix.homeManagerModules.default

    ./modules/ag.nix
    ./modules/browsers.nix
    ./modules/autostart.nix
    ./modules/registry.nix
    ./modules/email.nix
    ./secrets.nix

    ./programs/git.nix
    ./programs/kitty.nix
    # ./programs/vscode.nix
    # ./programs/nvf.nix
    ./programs/bash.nix
    ./programs/fish.nix
    ./programs/shell-utils.nix
    ./programs/starship.nix
    ./programs/obs.nix
  ];

  config = {
    # Home Manager needs a bit of information about you and the paths it should
    # manage.
    home.username = "beat";
    home.homeDirectory = "/home/beat";

    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    #
    # You should not change this value, even if you update Home Manager. If you do
    # want to update the value, then make sure to first check the Home Manager
    # release notes.
    home.stateVersion = "22.11"; # Please read the comment before changing.

    home.packages =
      with pkgs;
      [
        # CLI packages in ./programs/shell-utils.nix

        # for secrets
        agenix

        # Nix language servers
        nixd

        # For easy shell-ish stuff
        racket

        # for `alles`
        alles
        ydotool
        wl-clipboard

        # Emacs
        ((emacsPackagesFor emacs30).emacsWithPackages (epkgs: [ epkgs.mu4e ]))
        ripgrep
        fd
        emacs-lsp-booster

        # For screen flickering notification
        brightnessctl

        # AI
        aider-chat-with-playwright
        python314
        claude-code
        claude-agent-acp
        codex
        codex-acp
        gemini-cli
        opencode
        # For claude code voice mode
        sox

        # Better haskell tooling
        inputs.hx.packages.${stdenv.hostPlatform.system}.default

        # NOTE: Enable gastown as soon as go 1.25.6 is here
        # Even though go 1.25.7 is here, the derivation is still broken –
        # a local checkout works for now.
        inputs.gastown.packages.${stdenv.hostPlatform.system}.default
        inputs.beads.packages.${stdenv.hostPlatform.system}.default
        dolt
        go

        # Install globally to make gleam-ts-mode happy
        gleam

        # Neovim
        neovim
        zig
        gcc
        lua
        unzip
        gnumake
        markdownlint-cli

        # other GUI Tools
        pcmanfm # a file viewer that just runs and doesn't wait ages for some search/tracker/miner database job that isn't there
        zed-editor
        chromium
        librewolf
        obsidian
        discord
        signal-desktop
        telegram-desktop
        zoom-us
        thunderbird
        gnome-tweaks
        teams-for-linux
        slack

        # DoneThat
        (import ./programs/donethat.nix { inherit pkgs; })
        # gnome-screenshot is non-functional on GNOME Wayland (silent no-op).
        # donethat-screenshot wraps Recursing's portal-based capture script;
        # point donethat's screenshot tool setting at `donethat-screenshot -f "%s"`.
        (import ./programs/donethat-screenshot.nix { inherit pkgs; })

        # Useful for login networks: https://discourse.nixos.org/t/does-wifionice-wifi-on-deutsche-bahn-german-railway-work-for-you/41646
        captive-browser

        # # It is sometimes useful to fine-tune packages, for example, by applying
        # # overrides. You can do that directly here, just don't forget the
        # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
        # # fonts?
        # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

        # # You can also create simple shell scripts directly inside your
        # # configuration. For example, this adds a command 'my-hello' to your
        # # environment:
        # (pkgs.writeShellScriptBin "my-hello" ''
        #   echo "Hello, ${config.home.username}!"
        # '')
      ]
      ++ [
        inputs.nixpkgs-24-11.legacyPackages."x86_64-linux".linphone
        pkgs.gnomeExtensions.run-or-raise
      ];

    home.file = {
      ".config/run-or-raise/shortcuts.conf".source = dotfiles/shortcuts.conf;
      ".config/custom-tab-title-from-file/config.json".source =
        dotfiles/custom-tab-title-from-file/config.json;

      ".config/zed/settings.json".source = dotfiles/zed/settings.json;
      ".config/zed/keymap.json".source = dotfiles/zed/keymap.json;

      ".config/opencode/tui.json".source = dotfiles/opencode/tui.json;

      ".mob".source = dotfiles/mob.sh/.mob;
      ".markdownlint.json".text = builtins.toJSON {
        "blanks-around-lists" = false;
        "blanks-around-headings" = false;
        "blanks-around-fences" = false;
        "no-bare-urls" = false;
        "first-line-heading" = false;
        "single-h1" = false;
        "line-length" = false;
      };
    };

    # You can also manage environment variables but you will have to manually
    # source
    #
    #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
    #
    # or
    #
    #  /etc/profiles/per-user/beat/etc/profile.d/hm-session-vars.sh
    #
    # if you don't want to manage your shell through Home Manager.
    home.sessionVariables = {
      GNOME_SHELL_SLOWDOWN_FACTOR = 0.35;
      # https://emacs-lsp.github.io/lsp-mode/page/performance/#use-plists-for-deserialization
      LSP_USE_PLISTS = "true";
    };

    xdg.enable = true;
    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome
      ];
      config.common = {
        # Default to the gtk backend (honors mimeapps.list, works without
        # Nautilus). Only route screen sharing to the gnome backend, since
        # Mutter is the only implementation that works under Wayland.
        default = "gtk";
        "org.freedesktop.impl.portal.ScreenCast" = "gnome";
        "org.freedesktop.impl.portal.RemoteDesktop" = "gnome";
      };
    };

    dconf.settings = {
      "org/gnome/desktop/input-sources" = {
        xkb-options = [ "terminate:ctrl_alt_bksp" ];
      };

      "org/gnome/desktop/interface" = {
        clock-format = "24h";
        clock-show-date = true;
        clock-show-seconds = true;
        color-scheme = "prefer-dark";
        show-battery-percentage = true;
        text-scaling-factor = 1.21;
      };

      "org/gnome/desktop/notifications" = {
        show-banners = false;
      };

      "org/gnome/desktop/search-providers" = {
        disable-external = true;
      };

      "org/gnome/desktop/session" = {
        idle-delay = lib.hm.gvariant.mkUint32 0;
      };

      "org/gnome/desktop/wm/keybindings" = {
        activate-window-menu = [ ];
        minimize = [ ];
        switch-windows = [ "<Super>Tab" ];
        switch-windows-backward = [ "<Shift><Super>Tab" ];
      };

      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:close";
      };

      "org/gnome/nautilus/list-view" = {
        use-tree-view = true;
      };

      "org/gnome/nautilus/preferences" = {
        default-folder-viewer = "list-view";
      };

      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        ];
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = "<Shift><Super>n";
        command =
          let
            toggle = pkgs.writeShellScript "toggle-night-light" ''
              current=$(gsettings get org.gnome.settings-daemon.plugins.color night-light-enabled)
              if [ "$current" = "true" ]; then
                gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled false
              else
                gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
              fi
            '';
          in
          toString toggle;
        name = "Toggle Night Light";
      };

      "org/gnome/settings-daemon/plugins/power" = {
        idle-dim = false;
      };

      "org/gnome/shell" = {
        disable-user-extensions = false;

        enabled-extensions = [ "run-or-raise@edvard.cz" ];
      };
      "org/gnome/shell/keybindings" = {
        toggle-message-tray = [ ];
        toggle-quick-settings = [ ];
        focus-active-notification = [ ];
        toggle-application-view = [ ];
      };
    };

    programs.home-manager.enable = true;

    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";

        prompt = "enabled";
      };
    };

    programs.ghostty = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      clearDefaultKeybinds = true;
      settings = {
        font-size = 10;
        keybind = [
          "ctrl+t=new_tab"
          "alt+left=previous_tab"
          "alt+right=next_tab"
          "alt+shift+left=move_tab:-1"
          "alt+shift+right=move_tab:1"
          "ctrl+]=new_split:right"
          "ctrl+[=new_split:down"
          "shift+left=goto_split:left"
          "shift+right=goto_split:right"
          "shift+up=goto_split:up"
          "shift+down=goto_split:down"
          "ctrl+equal=reset_font_size"
          "ctrl+minus=decrease_font_size:1"
          # ctrl+s
          # ctrl+g
          # "ctrl+plus=increase_font_size:1"
        ];
      };
    };

    programs.nix-index = {
      enable = true;
      enableBashIntegration = true;
      # enableFishIntegration = true;
    };

    catppuccin = {
      autoEnable = true;
      enable = true;
      flavor = "mocha";
      starship.enable = true;
      kitty.enable = true;
      gtk.icon.enable = true;
      fzf.enable = true;
      bat.enable = true;
      # Disable cause rebuilds all the time for ages
      # cursors.enable = true;
    };
  };
}
