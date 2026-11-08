{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.vimium-options.homeManagerModules.vimium-options
  ];

  # Sites chromium-app opens as installed web apps. modules/chromium-web-apps.nix
  # installs them by policy, run-or-raise.nix matches their windows by app id.
  options.chromiumApps = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.appId = lib.mkOption {
          type = lib.types.str;
          description = ''
            Chromium's id of the app with manifest id "https://<host>/": SHA-256
            of that string's SHA-256 digest, its first 32 hex digits as a-p.
            Nix can't hash raw bytes, so it's spelled out (chromium-app computes
            it the same way).
          '';
        };
      }
    );
    default = { };
    description = "Web apps by host.";
  };

  config.chromiumApps = {
    "todos.humane.tools".appId = "blhbelgpfcbaelngdfodkjeilpkkamjm";
    "links.humane.tools".appId = "allbonajpeebhnnehlfndkgkhbmbncoc";
    "mail.humane.tools".appId = "bljcfpkbhjjjcjglcknjnndjpaoedkkk";
    "flow.humane.tools".appId = "alcbjnnfdefohcilaaflckadfneglggi";
  };

  # Opens a URL as a Chromium app window in its own user data dir, so the
  # extensions of the main profile (Bitwarden, Vimium, ...) stay out of it.
  # All app windows share this dir, and with it their logins.
  #
  # When the site is installed there as a web app (see chromiumApps above),
  # it opens as that app: only then does
  # Chromium read its manifest, e.g. a display_override of
  # "window-controls-overlay", which lets the page draw into the title bar
  # (the chevron in the title bar toggles it).
  config.home.packages = [
    (pkgs.writeShellScriptBin "chromium-app" ''
      PATH=${pkgs.coreutils}/bin:$PATH
      dir="''${XDG_CONFIG_HOME:-$HOME/.config}/chromium-apps"
      origin=$(printf '%s' "$1" | ${pkgs.gnused}/bin/sed -E 's#^(https?://[^/]+).*#\1#')
      # Chromium's app id: SHA-256 of the manifest id's SHA-256 digest, its
      # first 32 hex digits as a-p.
      id=$(printf '%s/' "$origin" | sha256sum | cut -c1-64 | tr a-f A-F | basenc --base16 -d | sha256sum | cut -c1-32 | tr 0-9a-f a-p)
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

  config.programs.firefox =
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

  config.home.vimiumOptions = {
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
