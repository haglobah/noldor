{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    inputs.vimium-options.homeManagerModules.vimium-options
  ];

  # Opens a URL as a Chromium app window in its own user data dir, so the
  # extensions of the main profile (Bitwarden, Vimium, ...) stay out of it.
  # All app windows share this dir, and with it their logins.
  home.packages = [
    (pkgs.writeShellScriptBin "chromium-app" ''
      exec ${pkgs.chromium}/bin/chromium-browser \
        --user-data-dir="''${XDG_CONFIG_HOME:-$HOME/.config}/chromium-apps" \
        --no-first-run \
        --no-default-browser-check \
        --app="$1"
    '')
  ];

  programs.firefox =
    let
      extensionPkgs = with inputs.firefox-addons.packages."x86_64-linux"; [
        custom-tab-title-from-file
        bitwarden
        darkreader
        videospeed
        vimium
        ublock-origin
      ];
    in
    {
      enable = true;
      # TODO: replace with ${config.xdg.configHome}/mozilla/firefox, and then delete the former at some point
      configPath = ".mozilla/firefox";
      profiles.beat = {
        isDefault = true;
        id = 0;
        name = "beat";
        settings = {
          "signon.rememberSignons" = false;
          "layout.spellcheckDefault" = "0";
        };

        extensions.packages = extensionPkgs;
        extensions.force = true;

        search = {
          force = true;
          engines = {
            "Kagi" = {
              urls = [
                {
                  template = "https://kagi.com/search?";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://assets.kagi.com/v2/favicon-32x32.png";
              updateInterval = 24 * 60 * 60 * 1000; # every day
              definedAliases = [ "@kg" ];
            };
          };
        };
      };
    };

  home.vimiumOptions = {
    enable = true;

    outputFilePath = ".cache/vimium-options.json";

    keyMappings = {
      unmapAll = true;
      map = {
        l = "scrollPageDown";
        u = "scrollPageUp";
        f = "LinkHints.activateMode";
        p = "LinkHints.activateModeToOpenInNewTab";
        x = "createTab https://claude.ai";
      };
    };

    exclusionRules = [
      {
        passKeys = "";
        pattern = "https?://mail.google.com/*";
      }
    ];
  };
}
