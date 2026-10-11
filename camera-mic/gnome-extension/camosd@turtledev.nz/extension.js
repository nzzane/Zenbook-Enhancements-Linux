// Camera OSD - expose a D-Bus method that shows the standard GNOME OSD popup
// for webcam on/off (same style as the mic-mute key).
//
// org.gnome.Shell.ShowOSD only accepts gnome-settings-daemon as caller, so
// /usr/local/bin/camtoggle calls this instead:
//   gdbus call --session --dest org.gnome.Shell --object-path /nz/turtledev/CamOSD \
//     --method nz.turtledev.CamOSD.Show true

import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `
<node>
  <interface name="nz.turtledev.CamOSD">
    <method name="Show">
      <arg type="b" direction="in" name="enabled"/>
    </method>
  </interface>
</node>`;

export default class CamOsdExtension extends Extension {
    enable() {
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/nz/turtledev/CamOSD');
    }

    disable() {
        this._dbus?.unexport();
        this._dbus = null;
    }

    Show(enabled) {
        const icon = Gio.ThemedIcon.new(enabled ? 'camera-web-symbolic' : 'camera-disabled-symbolic');
        Main.osdWindowManager.showAll(icon, enabled ? 'Camera On' : 'Camera Off', null, null);
    }
}
