// Zen mode: Super+Z blurs and freezes every window but the focused one, blocks window
// switching and mutes notification banners. Ctrl+Alt+Super+Escape ends it.
// Closing the zen window or disabling the extension ends it too.
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {ExtensionState} from 'resource:///org/gnome/shell/misc/extensionUtils.js';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

// Keybindings that switch windows, workspaces or open the overview.
const BLOCKED = new RegExp('^(' + [
    'switch-(applications|windows|group|panels)',
    'switch-to-(workspace|application)-',
    'cycle-',
    'toggle-(overview|application-view|message-tray|quick-settings)',
    'overlay-key$',
    'shift-overview-',
    'show-desktop$',
    'minimize$',
    'panel-run-dialog$',
    'focus-active-notification$',
].join('|') + ')');

// Only these window types get blurred; menus and tooltips stay sharp.
const BLURRED_TYPES = [
    Meta.WindowType.NORMAL,
    Meta.WindowType.DIALOG,
    Meta.WindowType.MODAL_DIALOG,
    Meta.WindowType.UTILITY,
];

const EFFECT = 'zen-blur';
const SNAPSHOT = 'zen-snapshot';

// run-or-raise grabs its shortcuts as accelerators, which the keybinding
// filter cannot tell apart from media keys. Zen blocks its signal handler.
const RUN_OR_RAISE = 'run-or-raise@edvard.cz';

class Zen {
    constructor(window, settings, onEnd) {
        this._window = window;
        this._settings = settings;
        this._signals = [];
        this._blurred = new Map(); // actor => {signals, snapshot, hidden}
        this._pausedHandler = null;
        this._injections = new InjectionManager();

        // Direct scanout shows a fullscreen window without compositing,
        // which skips its blur. Mutter allows it despite static effects.
        global.compositor.disable_unredirect();
        for (const actor of global.get_window_actors())
            this._blur(actor);
        this._connect(global.window_manager, 'map', (wm, actor) => this._blur(actor));
        this._connect(global.window_manager, 'filter-keybinding',
            (wm, binding) => BLOCKED.test(binding.get_name()));
        this._connect(global.display, 'notify::focus-window', () => this._guardFocus());
        this._connect(window, 'unmanaging', onEnd);
        this._connect(Main.extensionManager, 'extension-state-changed', (manager, extension) => {
            if (extension.uuid === RUN_OR_RAISE)
                this._pauseRunOrRaise();
        });
        this._pauseRunOrRaise();

        // The hot corner and gestures open the overview without a keybinding.
        for (const method of ['show', 'toggle', 'showApps'])
            this._injections.overrideMethod(Main.overview, method, () => () => {});

        const notifications = new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'});
        if (notifications.get_boolean('show-banners')) {
            settings.set_boolean('banners-muted', true);
            notifications.set_boolean('show-banners', false);
        }
    }

    destroy() {
        unmuteBanners(this._settings);
        this._injections.clear();
        this._resumeRunOrRaise();
        for (const [object, id] of this._signals)
            object.disconnect(id);
        this._signals = [];
        for (const [actor, blurred] of this._blurred) {
            for (const id of blurred.signals)
                actor.disconnect(id);
            blurred.snapshot.destroy();
            for (const [child, opacity] of blurred.hidden)
                child.opacity = opacity;
            actor.remove_effect_by_name(EFFECT);
        }
        this._blurred.clear();
        global.compositor.enable_unredirect();
    }

    _connect(object, signal, handler) {
        this._signals.push([object, object.connect(signal, handler)]);
    }

    // The zen window and the dialogs it opens.
    _isZen(window) {
        for (let w = window; w; w = w.get_transient_for()) {
            if (w === this._window)
                return true;
        }
        return false;
    }

    _blur(actor) {
        const window = actor.meta_window;
        if (!window || this._isZen(window) || this._blurred.has(actor) ||
            !BLURRED_TYPES.includes(window.get_window_type()))
            return;
        actor.add_effect_with_name(EFFECT, new Shell.BlurEffect({
            radius: 40,
            brightness: 0.6,
            mode: Shell.BlurMode.ACTOR,
        }));
        this._blurred.set(actor, this._freeze(actor));
    }

    // Cover the window with a snapshot and hide its live surfaces, so
    // nothing that happens in it shows through the blur.
    _freeze(actor) {
        let content = null;
        try {
            content = actor.paint_to_content(null);
        } catch (e) {
            console.error(`zen: cannot snapshot "${actor.meta_window.title}"; hiding it instead: ${e}`);
        }
        const hidden = new Map(); // child => its opacity
        const hide = child => {
            if (child.name === SNAPSHOT || hidden.has(child))
                return;
            hidden.set(child, child.opacity);
            child.opacity = 0;
        };
        actor.get_children().forEach(hide);
        const snapshot = new Clutter.Actor({
            name: SNAPSHOT,
            content,
            width: actor.width,
            height: actor.height,
        });
        actor.add_child(snapshot);
        const signals = [
            actor.connect('child-added', (a, child) => hide(child)),
            actor.connect('child-removed', (a, child) => hidden.delete(child)),
            actor.connect('destroy', () => this._blurred.delete(actor)),
        ];
        return {signals, snapshot, hidden};
    }

    // Clicks, new windows and gestures can move focus; send it back. Focus
    // may leave for the lock screen and system dialogs.
    _guardFocus() {
        const focus = global.display.focus_window;
        if (focus && this._isZen(focus))
            return;
        if (Main.actionMode !== Shell.ActionMode.NORMAL)
            return;
        Main.activateWindow(this._window);
    }

    _pauseRunOrRaise() {
        const extension = Main.extensionManager.lookup(RUN_OR_RAISE);
        if (extension?.state !== ExtensionState.ACTIVE)
            return;
        const handler = extension.stateObj.app?.handler_accelerator_activated;
        if (!handler) {
            console.error('zen: cannot find the run-or-raise shortcut handler; its shortcuts stay active');
            return;
        }
        if (handler === this._pausedHandler)
            return;
        GObject.signal_handler_block(global.display, handler);
        this._pausedHandler = handler;
    }

    _resumeRunOrRaise() {
        if (this._pausedHandler &&
            GObject.signal_handler_is_connected(global.display, this._pausedHandler))
            GObject.signal_handler_unblock(global.display, this._pausedHandler);
        this._pausedHandler = null;
    }
}

// Turn banners back on if zen turned them off, also after a shell crash.
function unmuteBanners(settings) {
    if (!settings.get_boolean('banners-muted'))
        return;
    new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'})
        .set_boolean('show-banners', true);
    settings.set_boolean('banners-muted', false);
}

export default class ZenExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._zen = null;
        unmuteBanners(this._settings);
        Main.wm.addKeybinding('enter-zen', this._settings, Meta.KeyBindingFlags.NONE,
            Shell.ActionMode.NORMAL, () => this._enter());
        Main.wm.addKeybinding('exit-zen', this._settings, Meta.KeyBindingFlags.NONE,
            Shell.ActionMode.NORMAL, () => this._exit());
    }

    disable() {
        this._exit();
        Main.wm.removeKeybinding('enter-zen');
        Main.wm.removeKeybinding('exit-zen');
        this._settings = null;
    }

    _enter() {
        const window = global.display.focus_window;
        if (this._zen || !window)
            return;
        this._zen = new Zen(window, this._settings, () => this._exit());
    }

    _exit() {
        this._zen?.destroy();
        this._zen = null;
    }
}
