# GNOME VM test of the zen extension (home/pkgs/zen). Alice logs in to
# GNOME with the extension and run-or-raise enabled. The test types keys
# through QEMU and reads the shell's state over org.gnome.Shell.Eval.
{ pkgs, ... }:
let
  zen = pkgs.callPackage ../home/pkgs/zen { };
  runOrRaise = pkgs.gnomeExtensions.run-or-raise;
  # Super+B raises the window titled "beta". Super+U matches no window, so
  # it runs its command, which leaves a marker file.
  shortcuts = pkgs.writeText "shortcuts.conf" ''
    <Super>b,true,,/^beta$/
    <Super>u,${pkgs.coreutils}/bin/touch /home/alice/run-or-raise-fired,,/^none$/
  '';
in
pkgs.testers.runNixOSTest {
  name = "zen";

  nodes.machine = {
    imports = [ "${pkgs.path}/nixos/tests/common/user-account.nix" ];

    virtualisation.memorySize = 2048;

    services.displayManager.gdm.enable = true;
    services.displayManager.autoLogin = {
      enable = true;
      user = "alice";
    };
    services.desktopManager.gnome.enable = true;

    # Eval only works in unsafe mode.
    systemd.user.services."org.gnome.Shell@".serviceConfig.ExecStart = [
      ""
      "${pkgs.gnome-shell}/bin/gnome-shell --unsafe-mode"
    ];

    environment.systemPackages = [
      zen
      runOrRaise
      pkgs.zenity
    ];

    programs.dconf.profiles.user.databases = [
      {
        settings = {
          "org/gnome/shell" = {
            enabled-extensions = [
              zen.extensionUuid
              runOrRaise.extensionUuid
            ];
            welcome-dialog-last-shown-version = "999";
          };
          "org/gnome/desktop/wm/keybindings" = {
            switch-windows = [ "<Super>Tab" ];
            switch-windows-backward = [ "<Shift><Super>Tab" ];
          };
        };
      }
    ];

    systemd.tmpfiles.rules = [
      "d /home/alice/.config 0755 alice users -"
      "d /home/alice/.config/run-or-raise 0755 alice users -"
      "L+ /home/alice/.config/run-or-raise/shortcuts.conf - - - - ${shortcuts}"
    ];
  };

  testScript =
    { nodes, ... }:
    let
      uid = toString nodes.machine.users.users.alice.uid;
    in
    ''
      import json
      import shlex
      import time

      def js(code):
          """Evaluate code in GNOME Shell and return its JSON result."""
          out = machine.succeed(
              "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/${uid} "
              "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus "
              "busctl --user --json=short call org.gnome.Shell /org/gnome/Shell "
              f"org.gnome.Shell Eval s {shlex.quote(code)}"
          )
          ok, result = json.loads(out)["data"]
          assert ok, f"Eval failed: {code}: {result}"
          return json.loads(result) if result else None

      def state():
          return js("""({
              focus: global.display.focus_window?.title ?? null,
              blurred: Object.fromEntries(global.get_window_actors().map(a => [
                  a.meta_window.title,
                  a.get_effects().some(e => e instanceof Shell.BlurEffect)])),
              overview: Main.overview.visible,
              banners: new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'})
                  .get_boolean('show-banners'),
          })""")

      def wait_for(predicate, what, timeout=30):
          deadline = time.monotonic() + timeout
          while time.monotonic() < deadline:
              if predicate(state()):
                  return
              time.sleep(0.5)
          raise AssertionError(f"Timed out waiting for {what}: {state()}")

      def focus_is(title):
          return lambda s: s["focus"] == title

      def stays(predicate, what):
          """Give the shell time to act on input that must have no effect."""
          time.sleep(2)
          assert predicate(state()), f"{what}: {state()}"

      def spawn(title):
          js(f"GLib.spawn_command_line_async('${pkgs.zenity}/bin/zenity --info --title={title} --text={title}')")

      def activate(title):
          js(f"Main.activateWindow(global.display.list_all_windows().find(w => w.title === '{title}'))")

      def press(keys):
          machine.send_key(keys)

      enter = "meta_l-z"
      leave = "ctrl-alt-meta_l-esc"

      def in_zen(s):
          return s["blurred"].get("beta") and not s["blurred"].get("alpha")

      def no_blur(s):
          return not any(s["blurred"].values())

      with subtest("GNOME starts with the extensions enabled"):
          machine.wait_for_unit("display-manager.service")
          machine.wait_for_file("/run/user/${uid}/wayland-0")
          machine.wait_until_succeeds(
              "runuser -u alice -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus "
              "gdbus call --session -d org.gnome.Shell -o /org/gnome/Shell "
              "-m org.gnome.Shell.Eval Main.layoutManager._startingUp | grep -q 'true,..false'"
          )
          for uuid in ["${zen.extensionUuid}", "${runOrRaise.extensionUuid}"]:
              assert js(f"Main.extensionManager.lookup('{uuid}')?.state") == 1, uuid
          js("Main.overview.hide()")
          spawn("beta")
          wait_for(focus_is("beta"), "beta")
          spawn("alpha")
          wait_for(focus_is("alpha"), "alpha")

      with subtest("Outside zen, switching works"):
          press("meta_l-tab")
          wait_for(focus_is("beta"), "Super+Tab to beta")
          activate("alpha")
          wait_for(focus_is("alpha"), "alpha")
          press("meta_l-b")
          wait_for(focus_is("beta"), "run-or-raise to raise beta")
          activate("alpha")
          wait_for(focus_is("alpha"), "alpha")

      with subtest("Super+Z blurs every window but the focused one"):
          press(enter)
          wait_for(in_zen, "zen")
          assert not state()["banners"], "banners stay on in zen"
          machine.screenshot("zen")

      with subtest("Window switching does nothing in zen"):
          for keys in ["meta_l-tab", "alt-tab", "alt-esc", "meta_l-b", "meta_l-page_down"]:
              press(keys)
              stays(focus_is("alpha"), keys)
          press("meta_l-u")
          time.sleep(2)
          machine.fail("test -e /home/alice/run-or-raise-fired")
          press("meta_l")
          stays(lambda s: not s["overview"], "Super opened the overview")
          js("Main.overview.toggle()")
          stays(lambda s: not s["overview"], "the hot corner path opened the overview")

      with subtest("Focus returns to the zen window"):
          activate("beta")
          wait_for(focus_is("alpha"), "focus to return")
          spawn("gamma")
          wait_for(lambda s: s["blurred"].get("gamma"), "gamma to be blurred")
          wait_for(focus_is("alpha"), "focus to return from gamma")

      with subtest("Ctrl+Alt+Super+Escape restores everything"):
          press(leave)
          wait_for(no_blur, "zen to end")
          assert state()["banners"], "banners stay off after zen"
          press("meta_l-u")
          machine.wait_for_file("/home/alice/run-or-raise-fired")
          press("meta_l-b")
          wait_for(focus_is("beta"), "run-or-raise after zen")
          activate("alpha")
          wait_for(focus_is("alpha"), "alpha")

      with subtest("Closing the zen window ends zen"):
          press(enter)
          wait_for(in_zen, "zen")
          js("global.display.focus_window.delete(global.get_current_time())")
          wait_for(lambda s: "alpha" not in s["blurred"] and no_blur(s), "zen to end")
          assert state()["banners"], "banners stay off after zen"

      with subtest("Disabling the extension ends zen"):
          activate("beta")
          wait_for(focus_is("beta"), "beta")
          press(enter)
          wait_for(lambda s: s["blurred"].get("gamma"), "zen")
          js("Main.extensionManager.disableExtension('${zen.extensionUuid}')")
          wait_for(no_blur, "zen to end")
          assert state()["banners"], "banners stay off after zen"
          press("meta_l-tab")
          wait_for(lambda s: s["focus"] != "beta", "Super+Tab after zen")

      with subtest("Banners muted by a crashed zen come back"):
          js("""(() => {
              new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'})
                  .set_boolean('show-banners', false);
              Main.extensionManager.lookup('${zen.extensionUuid}').stateObj
                  .getSettings().set_boolean('banners-muted', true);
          })()""")
          js("Main.extensionManager.enableExtension('${zen.extensionUuid}')")
          wait_for(lambda s: s["banners"], "banners to come back")
    '';
}
