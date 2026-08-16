# Zenbook Keyboard Brightness Adjust (Linux)

Make the ASUS Zenbook keyboard backlight **actually dim** on Linux — with
Secure Boot and kernel lockdown left enabled.

The kernel module is called `asus_kbd_pwkb`.

On the ASUS Zenbook S 14 (UX5406SA) the firmware only exposes 4 backlight
levels, and level 1 — the dimmest non-off setting — is 33% PWM duty. In a dark
room that is still glaring. The levels come from a 4-byte table in the DSDT:

```
\_SB.PC00.LPCB.EC0.PWKB = Buffer(4) { 0x00, 0x55, 0xAA, 0xFF }
                                        ^level0 ^1    ^2    ^3
```

The usual fix is to patch that byte in the DSDT and load the patched table
early via initrd — but overriding an ACPI table is blocked by
`LOCKDOWN_ACPI_TABLES`, so it requires disabling Secure Boot or kernel
lockdown. This module changes the same byte **at runtime instead**, using only
exported ACPICA calls that carry no lockdown hook. Secure Boot stays on,
lockdown stays at `integrity`, and the module itself is MOK-signed by DKMS.

Because it rewrites the data the *firmware's own* `SLKB` method reads, every
existing path keeps working and picks up the new value: the Fn hotkeys,
`/sys/class/leds/asus::kbd_backlight/brightness`, `asusctl`, resume-from-suspend,
all of it.

```
level 1: 0x55 (33% duty)  ->  0x0A (3.9% duty)
```

## Will it work on my machine?

Run the checker. It only reads — it dumps your DSDT, disassembles it, and looks
for the three things the module needs:

```bash
sudo dnf install acpica-tools      # or: sudo apt install acpica-tools
sudo ./check-compat.sh
```

```
ACPI table
  [ ok ] found PWKB at \_SB.PC00.LPCB.EC0.PWKB
  [ ok ] PWKB is a Buffer(4): 0x00 0x55 0xAA 0xFF
  [ ok ] found SLKB at \_SB.PC00.LPCB.EC0.SLKB
  [ ok ] found GLKB at \_SB.PC00.LPCB.EC0.GLKB
  [ ok ] path matches the module default -- no source edit needed

Verdict
  COMPATIBLE -- follow the README as written.
```

What it's checking, and what each answer means for you:

| Requirement | If it's missing |
|---|---|
| `PWKB` — a `Buffer(4)` of PWM duty values | **Dead end.** Your firmware doesn't drive the backlight from a duty table, and nothing here applies. |
| `SLKB` — the method that applies a level by indexing `PWKB` | **Dead end.** Nothing would push the new values to the EC. |
| `GLKB` — reads the current level | Works fine; load with `relevel=0..3` instead of the default `relevel=-1`. |
| The ACPI path matches `\_SB.PC00.LPCB.EC0` | Works fine, but edit `EC_PATH` in `asus_kbd_pwkb.c` and both paths in `kpws.asl`, then `make aml`. The checker prints your actual path. |

The checker also flags a level 1 that's already dim (nothing to gain), missing
kernel headers, missing DKMS, and whether Secure Boot means you'll need to
enroll a MOK.

It ends with a paste-ready block for a compatibility report — **please open an
issue with it either way**, working or not. That's how the table below grows.

### Tested hardware

| Model | BIOS | Kernel | PWKB path | Result |
|---|---|---|---|---|
| ASUS Zenbook S 14 UX5406SA | UX5406SA.309 | 7.1.8-200.fc44 (Fedora 44) | `\_SB.PC00.LPCB.EC0` | works, Secure Boot on, lockdown `integrity` |

Any ASUS machine whose DSDT has a `PWKB` `Buffer(4)` plus `SLKB`/`GLKB` should
work — this is EC firmware structure, not a per-model driver, so it is not
limited to Zenbooks. It just hasn't been confirmed anywhere else yet.

If you'd rather look by hand than run the script:

```bash
sudo acpidump -b -n DSDT -o dsdt.dat && iasl -d dsdt.dat
grep -n -B2 -A6 'PWKB\|SLKB\|GLKB' dsdt.dsl
```

## Requirements

```bash
# Fedora
sudo dnf install kernel-devel-$(uname -r) gcc make elfutils-libelf-devel dkms mokutil openssl
# Debian/Ubuntu
sudo apt install linux-headers-$(uname -r) build-essential dkms mokutil openssl
```

`acpica-tools` (for `iasl` and `acpidump`) is needed by `check-compat.sh`, and
with `python3` also to regenerate the AML.

## Install

### 1. Create a signing key (skip if you already have a MOK enrolled)

Secure Boot means the module has to be signed by a key the firmware trusts.
`ca.cnf` in this repo generates a suitable self-signed CA cert.

```bash
openssl req -new -x509 -nodes -days 3650 -config ca.cnf \
    -newkey rsa:4096 -keyout mok.key -outform DER -out mok.pub
```

`mok.key` is a **private key — never commit it**. `.gitignore` already excludes
both files.

### 2. Hand the key to DKMS *before* the first build

If you skip this, DKMS generates its own key and you'll enroll the wrong one.

```bash
sudo install -m600 mok.key /var/lib/dkms/mok.key
sudo install -m644 mok.pub /var/lib/dkms/mok.pub
```

### 3. Enroll the key in firmware

```bash
sudo mokutil --import /var/lib/dkms/mok.pub   # prompts for a one-time password
sudo reboot
```

On reboot, MokManager takes over the screen: **Enroll MOK → Continue → Yes →**
enter the one-time password → **Reboot**. This is the only reboot required.

### 4. Build and load

```bash
cd Zenbook-Keyboard-brightness-adjust-linux
sudo dkms add . && sudo dkms install asus-kbd-pwkb/0.1
sudo modprobe asus_kbd_pwkb
sudo dmesg | tail -3
```

Expected:

```
asus_kbd_pwkb: original PWKB = 00 55 aa ff
asus_kbd_pwkb: PWKB now 00 0a aa ff
```

Set the backlight to level 1 (Fn+F3 / the brightness keys) and look at it.

### 5. Make it permanent

```bash
echo "options asus_kbd_pwkb duty=0,10,45,140" | sudo tee /etc/modprobe.d/asus-kbd-pwkb.conf
echo asus_kbd_pwkb | sudo tee /etc/modules-load.d/asus_kbd_pwkb.conf
```

The first file pins your chosen duty values, the second loads the module at
boot. DKMS rebuilds and re-signs it automatically on kernel updates.

## Changing the brightness levels

The `duty` parameter is the whole table: four PWM duty bytes for backlight
levels 0, 1, 2 and 3. `0` = off, `255` = full brightness.

```
byte value   duty      byte value   duty
0x00    0     0.0%     0x55   85    33.3%   <- stock level 1
0x05    5     2.0%     0x80  128    50.2%
0x0A   10     3.9%     0xAA  170    66.7%   <- stock level 2
0x14   20     7.8%     0xFF  255   100.0%   <- stock level 3
0x20   32    12.5%
```

Tune it live, no reboot needed — `rmmod` restores the firmware's original table
every time, so the escape hatch is always one command:

```bash
sudo rmmod asus_kbd_pwkb                       # back to 00 55 aa ff
sudo modprobe asus_kbd_pwkb duty=0,20,170,255  # 0x14, less aggressive
```

`0x0A` is the value in use here for level 1. If your LED driver can't strike
that low (the backlight flickers, or just stays dark at level 1), step up:
`20`, then `32`.

Stock jumps from 33% straight to 67% and 100%, which is a cliff once level 1 is
down at 4%. Remapping the upper levels too gives a ramp that's roughly even to
the eye:

```
duty=0,10,45,140     # 0% / 3.9% / 17.6% / 54.9%   <- in use here
duty=0,10,45,180     # same, brighter top end for daylight
duty=0,10,64,160     # gentler dim end, gentler top end
```

Once you've picked values, put them in `/etc/modprobe.d/asus-kbd-pwkb.conf` as
shown above.

### `relevel`

After rewriting the table the module re-issues `SLKB` so the change is visible
immediately, instead of only after the next keypress.

| `relevel` | Behaviour |
|---|---|
| `-1` (default) | read the current level from firmware via `GLKB(2)` and re-apply it |
| `0`–`3` | force this level after patching |
| `-2` | don't touch the backlight at all |

```bash
sudo modprobe asus_kbd_pwkb duty=0,10,170,255 relevel=1
```

## Uninstall

```bash
sudo rm -f /etc/modules-load.d/asus_kbd_pwkb.conf /etc/modprobe.d/asus-kbd-pwkb.conf
sudo modprobe -r asus_kbd_pwkb          # restores the original PWKB table
sudo dkms remove asus-kbd-pwkb/0.1 --all
```

The MOK stays enrolled; remove it with `sudo mokutil --delete /var/lib/dkms/mok.pub`
(another reboot into MokManager) if you want it gone.

## How it works

Three ACPICA calls, none of which is gated by lockdown:

1. **`acpi_evaluate_object()` on the `PWKB` Name node** — reads and saves the
   original 4-byte buffer, so unload can put it back.
2. **`acpi_install_method()`** with an 89-byte SSDT containing exactly one
   `DefMethod`, `\_SB.PC00.LPCB.EC0.KPWS(Arg0)`, whose body is:
   ```asl
   CopyObject (Arg0, \_SB.PC00.LPCB.EC0.PWKB)
   Return (Zero)
   ```
   This is the trick that sidesteps `LOCKDOWN_ACPI_TABLES`: installing a single
   control method is not the same thing as overriding an ACPI table, and ACPICA
   documents it as supported ("If the method name already exists in the
   namespace, it is overwritten").
3. **`acpi_evaluate_object()` on `KPWS`** with a Buffer argument — AML
   `CopyObject` replaces the named `PWKB` object with our values. Then `SLKB(0x80 | level)`
   is re-issued so the panel updates on the spot.

Everything downstream — `asus-wmi` hotkeys, the LED class device,
`asus_hotk_resume()`, `hid-asus` — funnels into `SLKB`, which now indexes the
new table.

Source layout:

| File | |
|---|---|
| `asus_kbd_pwkb.c` | the module |
| `kpws.asl` | source for the injected helper method |
| `kpws_aml.h` | generated — compiled AML as a C byte array |
| `mkaml.py` | strips iasl's `If(Zero){External...}` prologue, fixes length + checksum |
| `Makefile` | kbuild + `make aml` |
| `dkms.conf` | DKMS packaging |
| `ca.cnf` | openssl config for the MOK signing cert |
| `check-compat.sh` | read-only DSDT compatibility checker |

### Regenerating the AML

Only needed if you edit `kpws.asl` (e.g. a different ACPI path):

```bash
sudo dnf install acpica-tools    # iasl
make aml                         # rewrites kpws_aml.h
```

## Caveats

- **The `KPWS` helper method stays installed until reboot.** ACPICA has no
  uninstall counterpart to `acpi_install_method()`. It is inert after unload —
  nothing calls it — and it's gone on the next boot.
- **Unload restores the table, but only if the module loaded cleanly.** If
  `acpi_install_method()` fails, nothing is changed at all.
- **Very low duty is a hardware question.** Some LED drivers won't strike below
  a threshold and will flicker or stay dark. That's what the `duty` parameter is
  for; a bad value costs you an `rmmod`.
- ACPI paths are model-specific. Verify `PWKB` exists in your DSDT before
  building.

## License

GPL-2.0. See [LICENSE](LICENSE).
