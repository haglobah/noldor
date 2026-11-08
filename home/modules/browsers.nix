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
  #
  # When the site is installed there as a web app (manifest id "/", see
  # chromiumAppId in run-or-raise.nix), it opens as that app: only then does
  # Chromium read its manifest, e.g. a display_override of
  # "window-controls-overlay", which lets the page draw into the title bar
  # (the chevron in the title bar toggles it). To install one, open the site
  # in a normal window of this dir (`chromium-browser
  # --user-data-dir=$HOME/.config/chromium-apps <url>`) and use the install
  # icon in the address bar.
  home.packages = [
    (pkgs.writeShellScriptBin "chromium-app" ''
      dir="''${XDG_CONFIG_HOME:-$HOME/.config}/chromium-apps"
      origin=$(printf '%s' "$1" | ${pkgs.gnused}/bin/sed -E 's#^(https?://[^/]+).*#\1#')
      # Chromium's app id: the manifest id's SHA-256, its first 32 hex digits as a-p.
      id=$(printf '%s/' "$origin" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -c1-32 | ${pkgs.coreutils}/bin/tr 0-9a-f a-p)
      if [ -d "$dir/Default/Web Applications/Manifest Resources/$id" ]; then
        app=(--app-id="$id")
      else
        app=(--app="$1")
      fi
      exec ${pkgs.chromium}/bin/chromium-browser \
        --user-data-dir="$dir" \
        --no-first-run \
        --no-default-browser-check \
        "''${app[@]}"
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
