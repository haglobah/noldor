{ config, lib, ... }:
{
  # Installs the home-manager users' chromiumApps (home/modules/browsers.nix)
  # as web apps, so chromium-app opens them with their manifest, e.g.
  # window-controls-overlay. The chevron in each app's title bar still needs
  # one click to hide the bar.
  #
  # Chromium reads this policy for every user data dir, so the apps also show
  # up in the main profile.
  programs.chromium = {
    enable = true;
    extraOpts.WebAppInstallForceList =
      map
        (host: {
          url = "https://${host}/";
          default_launch_container = "window";
          create_desktop_shortcut = false;
        })
        (
          lib.unique (
            lib.concatMap (user: lib.attrNames user.chromiumApps) (lib.attrValues config.home-manager.users)
          )
        );
  };
}
