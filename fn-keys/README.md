# Function keys

Part of [Zenbook Enhancements](../README.md).

## Media keys by default

asus-wmi turns Fn-lock on at boot, so the top row sends F1-F12 and you have to
press Fn+Esc after every boot to get the volume, brightness and other keys.
`asus-wmi-fnlock.conf` turns Fn-lock off at boot instead. Fn+key still gives
F1-F12, and Fn+Esc still switches modes while you're using the laptop.

```bash
cd Zenbook-Enhancements-Linux/fn-keys
sudo install -m644 asus-wmi-fnlock.conf /etc/modprobe.d/asus-wmi-fnlock.conf
```

It applies the next time asus-wmi loads, so reboot (the parameter can't be
changed while the module is loaded). Check with:

```bash
cat /sys/module/asus_wmi/parameters/fnlock_default    # N
```

## What the special keys send

Measured on a UX5406SA (BIOS .309) with Fn-lock off:

| Key | Sends | Handled by |
|---|---|---|
| F8 (emoji) | `Super`+`.` from the keyboard itself | the emoji picker below |
| F10 (camera) | `KEY_CAMERA` on "Asus WMI hotkeys" (`XF86WebCam`) | [camera-mic](../camera-mic/README.md) |
| F12 (MyASUS) | `KEY_PROG1` on "Asus WMI hotkeys" (`XF86Launch1`) | the fan level cycle in [fan](../fan/README.md) |

The keyboard backlight key is handled inside asus-wmi (see
[keyboard-backlight](../keyboard-backlight/README.md)) and the mic mute key by
GNOME, so neither needs anything here.

To check a key on your own machine:

```bash
sudo libinput debug-events --show-keycodes
```

## Emoji key (F8)

GNOME has no system-wide emoji popup, and IBus's own emoji shortcut does
nothing under GNOME, because GNOME disables the IBus panel. This binds the
key to [Smile](https://smile.mijorus.it/), a small emoji picker that pops up
like Win+. on Windows. Its companion extension pastes the chosen emoji into
the app you were typing in.

```bash
flatpak install flathub it.mijorus.smile
../gnome-keybinding.sh emoji 'Emoji picker' '<Super>period' 'flatpak run it.mijorus.smile'
```

Then install "Smile - complementary extension"
(`smile-extension@mijorus.it`) from
[extensions.gnome.org](https://extensions.gnome.org/extension/6096/smile-complementary-extension/)
and log out and back in. Without it Smile copies the emoji to the clipboard
instead of pasting. The extension pastes with Ctrl+V, so in a terminal paste
it yourself with Ctrl+Shift+V.
