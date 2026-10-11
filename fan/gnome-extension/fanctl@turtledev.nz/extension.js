// ASUS fan Quick Settings tile.
// The asus-wmi driver only offers full speed (pwm1_enable=0) or firmware auto (2);
// in auto, the curve follows the platform profile, set here via power-profiles D-Bus.
// The MyASUS key cycles Quiet -> Balanced -> Performance -> Full with a level OSD.
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

const FANCTL = '/usr/local/bin/fanctl';
const ICON = 'weather-windy-symbolic';
const POLL_SECONDS = 2;
// The MyASUS key (F12 in hotkey mode, KEY_PROG1) cycles the fan levels below.
const CYCLE_KEY = 'XF86Launch1';
const PPD_NAME = 'org.freedesktop.UPower.PowerProfiles';
const PPD_PATH = '/org/freedesktop/UPower/PowerProfiles';
const CURVES = [
    ['power-saver', 'Quiet curve'],
    ['balanced', 'Balanced curve'],
    ['performance', 'Performance curve'],
];

function findHwmon() {
    const dir = Gio.File.new_for_path('/sys/devices/platform/asus-nb-wmi/hwmon');
    try {
        const iter = dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
        for (let info; (info = iter.next_file(null));) {
            const path = `${dir.get_path()}/${info.get_name()}`;
            if (readSysfs(`${path}/name`) === 'asus')
                return path;
        }
    } catch {
        // Driver not loaded.
    }
    return null;
}

function readSysfs(path) {
    try {
        const [, bytes] = GLib.file_get_contents(path);
        return new TextDecoder().decode(bytes).trim();
    } catch {
        return null;
    }
}

const FanToggle = GObject.registerClass({
    Signals: {'fan-updated': {}},
}, class FanToggle extends QuickMenuToggle {
    _init() {
        super._init({title: 'Fan', iconName: ICON, toggleMode: false});
        this._hwmon = findHwmon();
        this._profile = null;

        this.menu.setHeader(ICON, 'Fan');
        this._autoItem = this.menu.addAction('Auto', () => this._setMode('auto'));
        this._fullItem = this.menu.addAction('Full speed', () => this._setMode('max'));
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem('Auto fan curve'));
        this._curveItems = CURVES.map(([profile, label]) =>
            [profile, this.menu.addAction(label, () => this._setProfile(profile))]);

        this.connect('clicked', () => this._setMode(this._isFull() ? 'auto' : 'max'));

        Gio.DBusProxy.new_for_bus(Gio.BusType.SYSTEM, Gio.DBusProxyFlags.NONE, null,
            PPD_NAME, PPD_PATH, PPD_NAME, null, (_o, res) => {
                try {
                    this._ppd = Gio.DBusProxy.new_for_bus_finish(res);
                    this._ppdId = this._ppd.connect('g-properties-changed', () => this._refresh());
                    this._refresh();
                } catch (e) {
                    logError(e, 'fanctl: power-profiles D-Bus unavailable');
                }
            });

        this._refresh();
        this._pollId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, POLL_SECONDS, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    // Levels for the MyASUS key: the three auto curves, then full speed.
    _level() {
        if (this._isFull())
            return CURVES.length;
        return Math.max(0, CURVES.findIndex(([p]) => p === this._profile));
    }

    cycle() {
        const next = (this._level() + 1) % (CURVES.length + 1);
        let label;
        if (next === CURVES.length) {
            this._setMode('max');
            label = 'Fan · Full speed';
        } else {
            if (this._isFull())
                this._setMode('auto');
            this._setProfile(CURVES[next][0]);
            label = `Fan · ${CURVES[next][1].replace(' curve', '')}`;
        }
        Main.osdWindowManager.showAll(Gio.ThemedIcon.new(ICON), label,
            (next + 1) / (CURVES.length + 1), 1);
    }

    _isFull() {
        return this._hwmon !== null && readSysfs(`${this._hwmon}/pwm1_enable`) === '0';
    }

    _refresh() {
        if (!this._hwmon)
            this._hwmon = findHwmon();
        if (!this._hwmon) {
            this.subtitle = 'Unavailable';
            this.checked = false;
            return;
        }
        const full = this._isFull();
        const rpm = readSysfs(`${this._hwmon}/fan1_input`) ?? '?';
        this._profile = this._ppd?.get_cached_property('ActiveProfile')?.unpack() ?? null;
        const curve = CURVES.find(([p]) => p === this._profile)?.[1].replace(' curve', '');
        const mode = full ? 'Full' : `Auto${curve ? ` · ${curve}` : ''}`;

        this.checked = full;
        this.subtitle = `${rpm} rpm · ${mode}`;
        this.menu.setHeader(ICON, 'Fan', `${rpm} rpm`);
        this._autoItem.setOrnament(full ? PopupMenu.Ornament.NONE : PopupMenu.Ornament.CHECK);
        this._fullItem.setOrnament(full ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        for (const [profile, item] of this._curveItems) {
            item.setOrnament(profile === this._profile
                ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        }
        this.emit('fan-updated');
    }

    _setMode(mode) {
        try {
            const proc = Gio.Subprocess.new([FANCTL, mode],
                Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDERR_SILENCE |
                Gio.SubprocessFlags.STDOUT_SILENCE);
            proc.wait_check_async(null, (_p, res) => {
                try {
                    proc.wait_check_finish(res);
                } catch (e) {
                    logError(e, `fanctl ${mode} failed`);
                }
                this._refresh();
            });
        } catch (e) {
            logError(e, 'fanctl: cannot run');
        }
    }

    _setProfile(profile) {
        this._ppd?.call('org.freedesktop.DBus.Properties.Set',
            new GLib.Variant('(ssv)', [PPD_NAME, 'ActiveProfile', new GLib.Variant('s', profile)]),
            Gio.DBusCallFlags.NONE, -1, null, (proxy, res) => {
                try {
                    proxy.call_finish(res);
                } catch (e) {
                    logError(e, `fanctl: set profile ${profile} failed`);
                }
                this._refresh();
            });
    }

    destroy() {
        if (this._pollId)
            GLib.source_remove(this._pollId);
        if (this._ppd && this._ppdId)
            this._ppd.disconnect(this._ppdId);
        this._pollId = this._ppdId = this._ppd = null;
        super.destroy();
    }
});

const FanIndicator = GObject.registerClass(
class FanIndicator extends SystemIndicator {
    _init() {
        super._init();
        // Panel icon only while the fan is forced to full speed.
        this._icon = this._addIndicator();
        this._icon.iconName = ICON;
        const toggle = this._toggle = new FanToggle();
        toggle.connect('fan-updated', () => (this._icon.visible = toggle.checked));
        this._icon.visible = toggle.checked;
        this.quickSettingsItems.push(toggle);
    }

    cycle() {
        this._toggle.cycle();
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class FanControlExtension extends Extension {
    enable() {
        this._indicator = new FanIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);

        this._action = global.display.grab_accelerator(CYCLE_KEY, Meta.KeyBindingFlags.NONE);
        if (this._action !== Meta.KeyBindingAction.NONE) {
            this._bindingName = Meta.external_binding_name_for_action(this._action);
            Main.wm.allowKeybinding(this._bindingName,
                Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW | Shell.ActionMode.POPUP);
            this._acceleratorId = global.display.connect('accelerator-activated',
                (_display, action) => {
                    if (action === this._action)
                        this._indicator?.cycle();
                });
        } else {
            console.warn(`fanctl: could not grab ${CYCLE_KEY}`);
        }
    }

    disable() {
        if (this._acceleratorId)
            global.display.disconnect(this._acceleratorId);
        if (this._bindingName)
            Main.wm.allowKeybinding(this._bindingName, Shell.ActionMode.NONE);
        if (this._action)
            global.display.ungrab_accelerator(this._action);
        this._acceleratorId = this._bindingName = this._action = null;
        this._indicator?.destroy();
        this._indicator = null;
    }
}
