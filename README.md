# Zenbook Enhancements (Linux)

You used AI: Yes, because I ain't digging that deep for keyboard control, but boy did Claude.
Works pretty well, can finally use the laptop in a dim room....

Fixes and extras for the ASUS Zenbook S 14 (UX5406SA) on Linux, so the
keyboard and its special keys work the way they do on Windows. Secure Boot and
kernel lockdown stay enabled throughout. Each part is independent; install
only the ones you want.

| Part | What you get |
|---|---|
| [keyboard-backlight](keyboard-backlight/README.md) | A keyboard backlight that actually dims: a runtime rewrite of the firmware's brightness table, plus an optional patched asus-wmi for up to 11 levels with a GNOME slider. |
| [camera-mic](camera-mic/README.md) | F10 really disconnects the webcam, the key LED shows the camera state, the off state survives reboots, a GNOME popup, and both key LEDs restored after suspend. |
| [fan](fan/README.md) | A Quick Settings fan tile with live RPM, and F12 (MyASUS) cycles Quiet → Balanced → Performance → Full speed with a volume-style popup. |
| [fn-keys](fn-keys/README.md) | Media keys by default instead of F1-F12, and the emoji key (F8) opens an emoji picker. |

`gnome-keybinding.sh` adds a GNOME custom shortcut without touching your
existing ones. The camera and emoji keys use it.

## Tested hardware

| Model | BIOS | Kernel | Desktop |
|---|---|---|---|
| ASUS Zenbook S 14 UX5406SA | UX5406SA.309 | 7.2.9-200.fc44 (Fedora 44) | GNOME 50 (Wayland) |

The keyboard backlight module works on any ASUS machine with the same ACPI
structure, and `keyboard-backlight/check-compat.sh` tells you whether yours
has it. The camera LED GPIO, USB IDs and key codes are specific to the
UX5406SA; the READMEs say what to change for other models. Compatibility
reports are welcome as issues, working or not.

## Troubleshooting

**All GNOME extensions turned off after a logout or reboot.** GNOME 50.5 can
crash while logging out. After a GNOME Shell crash, GNOME switches off every
user extension in case one of them caused it. Turn them back on with the main
switch in the Extensions app, or:

```bash
gsettings set org.gnome.shell disable-user-extensions false
```

**Keyboard backlight levels wrong after changing `duty=`.** See step 5 in
[keyboard-backlight](keyboard-backlight/README.md#5-make-it-permanent). The
module has to be kept out of the initramfs.

**F10 / F12 send F10 / F12 instead.** Fn-lock is on. Press Fn+Esc, or install
the [fn-keys](fn-keys/README.md) config.

## License

GPL-2.0. See [LICENSE](LICENSE).
