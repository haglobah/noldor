# Generates ~/.config/run-or-raise/shortcuts.conf for the run-or-raise GNOME
# extension. To reload the config, turn the extension off and on.
#
# Line format: shortcut[:mode],command,[wm_class],[title]
# wm_class and title are case sensitive; regexes go between slashes.
# How to know a window's wm_class? Use xprop or the looking glass tool.
{ lib, ... }:

let
  inherit (lib) concatMap concatStringsSep;

  mode = "switch-back-when-focused";

  # Title regexes: match windows whose title contains any / none of the patterns.
  anyOf = patterns: "/^.*(${concatStringsSep "|" patterns}).*$/";
  noneOf = patterns: "/^((?!${concatStringsSep "|" patterns}).)*$/";

  line =
    {
      key,
      command,
      wmClass ? "",
      title ? "",
    }:
    "${key}:${mode},${command},${wmClass},${title}";

  # Shortcuts that raise an app (or launch it if it has no window yet).
  apps = [
    {
      key = "<Super>t";
      command = "kitty --listen-on unix:@mykitty";
      wmClass = "kitty";
    }
    {
      key = "<Super>u";
      command = "thunderbird";
    }
    {
      key = "<Super>y";
      command = "linphone";
    }
    {
      key = "<Super>s";
      command = "signal-desktop";
      wmClass = "signal";
    }
    {
      key = "<Super>v";
      command = "discord";
      wmClass = "discord";
    }
    {
      key = "<Super>p";
      command = "pcmanfm";
      wmClass = "pcmanfm";
    }
    {
      key = "<Super>d";
      command = "donethat";
      wmClass = "donethat";
      title = "DoneThat";
    }
    {
      key = "<Ctrl><Shift>d";
      command = "donethat";
      wmClass = "donethat";
      title = "Chat";
    }
    {
      key = "<Super>h";
      command = "chromium-browser --app=https://todos.humane.tools";
      wmClass = "todos.humane.tools";
    }
  ];

  # Apps whose windows are split between shortcuts: each claim grabs the
  # windows whose titles match its patterns; the generic shortcut gets every
  # window the claims leave over. The generic exclusion regex is derived from
  # the claims, so adding a claim automatically takes its windows out of the
  # generic shortcut's reach.
  #
  # Claims inherit the generic wmClass unless they set their own.
  splitApps = [
    {
      generic = {
        key = "<Super>f";
        command = "firefox";
        wmClass = "firefox";
      };
      claims = [
        {
          key = "<Super>c";
          command = "firefox --new-window=https://calendar.google.com";
          titles = [ "Google Calendar" ];
        }
        {
          key = "<Super>m";
          command = "firefox --new-window=https://claude.ai";
          titles = [
            "claude\\.ai"
            "chatgpt\\.com"
            "gemini\\.google\\.com"
            "aistudio\\.google\\.com"
          ];
        }
        {
          key = "<Super>w";
          command = "firefox --new-window=https://web.whatsapp.com";
          titles = [
            "active-group\\.de"
            "Nirvana"
            "element\\.io"
            "Plausible"
            "PostHog"
            "Grafana"
            "web\\.whatsapp\\.com"
          ];
        }
      ];
    }
    {
      generic = {
        key = "<Super>g";
        command = "chromium";
        wmClass = "chromium-browser";
      };
      claims = [
        {
          key = "<Super>j";
          command = "chromium-browser --new-window=https://jitsi.active-group.de";
          titles = [
            "Jitsi"
            "BigBlueButton"
          ];
        }
      ];
    }
    {
      generic = {
        key = "<Super>e";
        command = "emacs";
        wmClass = "Emacs";
      };
      claims = [
        {
          key = "<Super>i";
          command = ''emacs --name "mycelium"'';
          wmClass = "";
          titles = [ "mycelium" ];
        }
      ];
    }
  ];

  splitAppLines =
    { generic, claims }:
    [ (line (generic // { title = noneOf (concatMap (claim: claim.titles) claims); })) ]
    ++ map (
      claim:
      line {
        inherit (claim) key command;
        wmClass = claim.wmClass or generic.wmClass or "";
        title = anyOf claim.titles;
      }
    ) claims;
in
{
  home.file.".config/run-or-raise/shortcuts.conf".text =
    concatStringsSep "\n" (map line apps ++ concatMap splitAppLines splitApps) + "\n";
}
