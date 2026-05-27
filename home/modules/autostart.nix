{
  pkgs,
  inputs,
  ...
}:
{
  home.file = {
    ".config/autostart/kitty-autostart.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Kitty Autostart
      Comment=Start kitty at GNOME login
      Exec=${pkgs.kitty}/bin/kitty --listen-on unix:@mykitty
      X-GNOME-Autostart-enabled=true
      OnlyShowIn=GNOME;
    '';
    ".config/autostart/emacs-mycelium.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Emacs Mycelium
      Comment=Start a separate Emacs instance sporting mycelium (and other docs stuff)
      Exec=${pkgs.emacs}/bin/emacs --name "mycelium"
      X-GNOME-Autostart-enabled=true
      OnlyShowIn=GNOME;
    '';
    ".config/autostart/todos-humane-tools.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=todos.humane.tools
      Comment=Start the todos.humane.tools PWA
      Exec=chromium-browser --app=https://todos.humane.tools
      X-GNOME-Autostart-enabled=true
      OnlyShowIn=GNOME;
    '';
    ".config/autostart/donethat.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Version=1.0
      Name=DoneThat
      Exec=${(import ../programs/donethat.nix { inherit pkgs; })}/bin/donethat --no-sandbox
      Terminal=false
      X-GNOME-Autostart-enabled=true
      X-GNOME-Autostart-Delay=5
    '';

    ".config/autostart/linphone.desktop".source = "${
      inputs.nixpkgs-24-11.legacyPackages."x86_64-linux".linphone
    }/share/applications/linphone.desktop";
    ".config/autostart/firefox.desktop".source = "${pkgs.firefox}/share/applications/firefox.desktop";
    ".config/autostart/thunderbird.desktop".source =
      "${pkgs.thunderbird}/share/applications/thunderbird.desktop";
    # ".config/autostart/librewolf.desktop".source =
    #   "${pkgs.librewolf}/share/applications/librewolf.desktop";
    ".config/autostart/chromium.desktop".source =
      "${pkgs.chromium}/share/applications/chromium-browser.desktop";
    ".config/autostart/emacs.desktop".source = "${pkgs.emacs}/share/applications/emacs.desktop";
    # ".config/autostart/obsidian.desktop".source =
    # "${pkgs.obsidian}/share/applications/obsidian.desktop";
  };
}
