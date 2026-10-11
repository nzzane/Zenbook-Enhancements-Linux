# Fan control

Part of [Zenbook Enhancements](../README.md).

The Zenbook S 14 (UX5406SA) has one fan, and asus-wmi exposes very little for
it: `pwm1_enable` = `0` runs it at full speed, `2` hands it back to the
firmware's automatic curve. There is no duty cycle and no custom curve.
(`pwm2_enable` returns `-EIO`; there is no second fan.) The only other lever is
the firmware platform profile (quiet / balanced / performance), which changes
the automatic curve along with the CPU power limits.

This puts both in reach:

- **A Quick Settings tile** with live RPM. Click it to switch between auto and
  full speed. Its menu picks the auto curve (quiet / balanced / performance).
- **The MyASUS key (F12) cycles the fan level** with a GNOME popup and level
  bar, like the volume keys: Quiet → Balanced → Performance → Full speed →
  Quiet.
- **`fanctl`** for the terminal: `fanctl {max|auto|toggle|status}`.

| Level | Fan | Platform profile | Bar |
|---|---|---|---|
| Quiet | auto | power-saver | 1/4 |
| Balanced | auto | balanced | 2/4 |
| Performance | auto | performance | 3/4 |
| Full speed | full | (unchanged) | 4/4 |

The quiet / balanced / performance levels are system power profiles, so they
also change CPU performance, the same as picking a power mode in GNOME.

## How it works

| Part | What it does |
|---|---|
| `fanctl` | Writes `pwm1_enable` on the `asus` hwmon device. |
| `99-asus-fan.rules` | Lets the `wheel` group write `pwm1_enable`, so no password is needed. |
| `gnome-extension/fanctl@turtledev.nz` | The Quick Settings tile, and the F12 binding. Sets the profile through the `org.freedesktop.UPower.PowerProfiles` D-Bus API. |

In hotkey mode the MyASUS key sends `KEY_PROG1` on "Asus WMI hotkeys", which
GNOME sees as `XF86Launch1`. The extension grabs that accelerator itself, so
there is no shortcut to set up. Fn+F12 is still plain F12.

## Requirements

- GNOME 50 for the extension. `fanctl` works anywhere.
- power-profiles-daemon, or tuned with `tuned-ppd` (Fedora's default), for the
  curve levels.
- Your user in the `wheel` group. On Debian/Ubuntu, change `wheel` to `sudo`
  in `99-asus-fan.rules`.

## Install

```bash
cd Zenbook-Enhancements-Linux/fan
sudo install -m755 fanctl /usr/local/bin/fanctl
sudo install -m644 99-asus-fan.rules /etc/udev/rules.d/99-asus-fan.rules
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=hwmon

cp -r gnome-extension/fanctl@turtledev.nz ~/.local/share/gnome-shell/extensions/
gnome-extensions enable fanctl@turtledev.nz    # log out and back in on Wayland

fanctl status
```

## Uninstall

```bash
fanctl auto
gnome-extensions disable fanctl@turtledev.nz
rm -rf ~/.local/share/gnome-shell/extensions/fanctl@turtledev.nz
sudo rm -f /usr/local/bin/fanctl /etc/udev/rules.d/99-asus-fan.rules
```
