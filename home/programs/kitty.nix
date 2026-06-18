{ ... }:
let
  # Repeat an SGR mouse wheel event N times so one keypress scrolls N lines.
  # Claude Code (and similar fullscreen TUIs) move ~1 line per wheel notch, so
  # 24 events ≈ half a page on a typical window. button 64 = up, 65 = down.
  wheel =
    direction: times:
    builtins.concatStringsSep "" (
      builtins.genList (_: "\\x1b[<${if direction == "up" then "64" else "65"};1;1M") times
    );
in
{
  programs.kitty = {
    enable = true;
    shellIntegration.enableBashIntegration = true;
    shellIntegration.enableFishIntegration = true;

    settings = {
      enabled_layouts = "splits:split_axis=horizontal";
      allow_remote_control = "yes";
      hide_window_decorations = "yes";
      font_size = 16;
      # This is for enabling a global visual bell. However, this doesn't seem to work (only makes the screen brighter, not less bright again)
      # enable_audio_bell = "no";
      # visual_bell_duration = 0;
      # command_on_bell = "${pkgs.brightnessctl}/bin/brightnessctl s +10%; sleep 0.05; ${pkgs.brightnessctl}/bin/brightnessctl s 10%-";
    };

    keybindings = {
      "ctrl+shift+space" = "push_keyboard_mode scroll";
      "ctrl+t" = "launch --cwd=current --type=tab";
      "ctrl+alt+c" =
        "launch --cwd=current --type=tab fish --interactive --init-command \"direnv exec . claude --model opus\"";
      "alt+left" = "prev_tab";
      "alt+right" = "next_tab";
      "alt+shift+left" = "move_tab_backward";
      "alt+shift+right" = "next_tab_forward";
      "ctrl+]" = "launch --cwd=current --location=vsplit";
      "ctrl+[" = "launch --cwd=current --location=hsplit";
      "shift+left" = "neighboring_window left";
      "shift+right" = "neighboring_window right";
      "shift+up" = "neighboring_window up";
      "shift+down" = "neighboring_window down";
      "ctrl+shift+left" = "move_window left";
      "ctrl+shift+right" = "move_window right";
      "ctrl+shift+up" = "move_window up";
      "ctrl+shift+down" = "move_window down";
      "ctrl+plus" = "change_font_size all +1.0";
      "ctrl+equal" = "change_font_size all 10.0";
      "ctrl+minus" = "change_font_size all -1.0";
      "ctrl+s" = "send_text all \\x17";
      "ctrl+g" = "send_key alt+d";
      "ctrl+h" = "remote_control scroll-window 0.5p+";
      "ctrl+," = "remote_control scroll-window 0.5p-";
      # Emulate mouse-wheel scroll for fullscreen TUIs (e.g. Claude Code) that
      # grab the mouse and render on the alternate screen, where kitty's own
      # scrollback (above) is empty. See the `wheel` helper at the top of file.
      "alt+h" = "send_text all ${wheel "down" 16}";
      "alt+," = "send_text all ${wheel "up" 16}";
    };

    extraConfig = ''
      # Scroll mode: bare arrows scroll, escape exits
      keyboard_mode scroll
          up         scroll_line_up
          down       scroll_line_down
          page_up    scroll_page_up
          page_down  scroll_page_down
          k          scroll_line_up
          j          scroll_line_down
          u          scroll_half_page_up
          l          scroll_half_page_down
          g          scroll_to_top
          shift+g    scroll_to_bottom
          escape     pop_keyboard_mode
          q          pop_keyboard_mode
          ctrl+c     pop_keyboard_mode
      end_keyboard_mode
    '';
  };
}
