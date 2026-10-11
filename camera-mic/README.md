# Camera and mic keys

Part of [Zenbook Enhancements](../README.md).

On the Zenbook S 14 (UX5406SA) the camera key (F10) does nothing useful under
Linux and its LED never lights. The mic mute key already works, but its LED can
go out after suspend. This makes both keys behave like they do on Windows:

- **F10 switches the webcam off for real.** The USB device is deauthorized, so
  `uvcvideo` unbinds and `/dev/video*` disappear. No app can open the camera
  until you press the key again.
- **The F10 LED shows the camera state**: lit while the camera is off, the same
  as the mic mute LED.
- **The off state survives reboots.** At boot a udev rule switches the camera
  off again if it was off when you shut down.
- **A GNOME popup** shows "Camera On" / "Camera Off", like the mic mute key.
- **Both LEDs are restored after suspend.** The firmware turns them off on
  S0ix entry.

## How it works

| Part | What it does |
|---|---|
| `camtoggle` | `camtoggle {on\|off\|toggle\|status}`. Writes the webcam's USB `authorized` attribute and creates/removes `/var/lib/camtoggle/disabled`. Bound to the camera key. |
| `camled` | Drives the F10 LED. `camled sync` sets it from the webcam state. Run by udev and the sleep hook, as root. |
| `99-asus-webcam.rules` | Lets the `wheel` group write `authorized`, switches the camera off at boot while the flag file exists, and runs `camled sync` whenever the camera appears or disappears. |
| `camled.sleep` | systemd sleep hook. After resume it re-syncs the camera LED and re-applies the mic LED trigger. |
| `gnome-extension/camosd@turtledev.nz` | Exposes a D-Bus method that shows the GNOME OSD popup. `org.gnome.Shell.ShowOSD` only accepts calls from gnome-settings-daemon, so `camtoggle` calls this instead. |

Hardware details, for anyone porting this to another model:

- The webcam is USB `3277:0059`. In hotkey mode the camera key sends
  `KEY_CAMERA` on "Asus WMI hotkeys", which GNOME sees as `XF86WebCam`.
- The F10 LED is GPIO pad `GPP_H_5` (ACPI pad `0x00180885`), line 31 of the
  `INTC105D:02` pin controller, active low: 0 = lit. The mic LED is `GPP_H_4`
  right next to it.
- asus-wmi doesn't register a camera LED on this model. The firmware puts the
  LED on WMI device `0x00060078`, where setting it only works once per boot and
  reading it is what actually drives the GPIO. Details and upstream status are
  in [kernel bug 221752](https://bugzilla.kernel.org/show_bug.cgi?id=221752).
  Until that is fixed in the kernel, `camled` drives the GPIO directly.
- The mic mute key needs nothing extra. It mutes the PipeWire source, which
  switches the ALSA `Dmic0 Capture Switch` off, so recordings are silence. The
  `platform::micmute` LED follows it through the `audio-micmute` trigger, and
  WirePlumber restores the mute state at login.

## Requirements

- `libgpiod-utils` 2.x for `gpioset` (`sudo dnf install libgpiod-utils`)
- GNOME 50 for the popup extension. Everything else works without GNOME.
- Your user in the `wheel` group. On Debian/Ubuntu, change `wheel` to `sudo`
  in `99-asus-webcam.rules` and below.

## Install

```bash
cd Zenbook-Enhancements-Linux/camera-mic
sudo install -m755 camtoggle /usr/local/bin/camtoggle
sudo install -Dm755 camled /usr/local/libexec/camled
sudo install -m755 camled.sleep /usr/lib/systemd/system-sleep/camled
sudo install -m644 99-asus-webcam.rules /etc/udev/rules.d/99-asus-webcam.rules
sudo install -d -o root -g wheel -m2775 /var/lib/camtoggle
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=3277

# Popup extension (log out and back in afterwards on Wayland)
cp -r gnome-extension/camosd@turtledev.nz ~/.local/share/gnome-shell/extensions/
gnome-extensions enable camosd@turtledev.nz

# Bind the camera key (keeps your other custom shortcuts)
../gnome-keybinding.sh camtoggle 'Toggle webcam' XF86WebCam '/usr/local/bin/camtoggle toggle'
```

Check it:

```bash
camtoggle off; ls /dev/video*      # no such file, F10 LED lit
camtoggle on;  ls /dev/video*      # devices back, LED off
```

## Security notes

- Anyone in `wheel` can switch the camera back on without a password, which is
  what makes the key work without a prompt. Malware running as your user could
  do the same. Turning the camera off is still a hard block for everything
  else: nothing can open a device that isn't there.
- The mic mute is a mute, not a disconnect. Any process running as you can
  unmute it with `wpctl` or `amixer`. The headset mic is a separate source.
- At boot the camera exists for a moment before the udev rule switches it off.
  That happens before login.

## Uninstall

```bash
sudo rm -f /usr/local/bin/camtoggle /usr/local/libexec/camled \
    /usr/lib/systemd/system-sleep/camled /etc/udev/rules.d/99-asus-webcam.rules
sudo rm -rf /var/lib/camtoggle
sudo udevadm control --reload
gnome-extensions disable camosd@turtledev.nz
rm -rf ~/.local/share/gnome-shell/extensions/camosd@turtledev.nz
```

If the camera was off, write `1` to its `authorized` file or reboot.
