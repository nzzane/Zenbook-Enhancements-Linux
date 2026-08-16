#!/usr/bin/env bash
#
# check-compat.sh -- will asus-kbd-pwkb work on this machine?
#
# Disassembles your DSDT and checks for the three things the module needs:
#   * a 4-byte Buffer named PWKB   (the PWM duty table it rewrites)
#   * a method SLKB                (firmware applies a level by indexing PWKB)
#   * a method GLKB                (reads the current level; optional)
# and reports the full ACPI path, so you know whether the module's built-in
# path works as-is or needs a one-line edit.
#
# Usage:
#   sudo ./check-compat.sh              # dump this machine's DSDT
#   ./check-compat.sh some/dsdt.dat     # inspect a DSDT you already have
#
# Needs: acpica-tools  (Fedora: dnf install acpica-tools / Debian: apt install acpica-tools)
#
# SPDX-License-Identifier: GPL-2.0

set -uo pipefail

DEFAULT_EC_PATH='\_SB.PC00.LPCB.EC0'   # what asus_kbd_pwkb.c ships with

ok()   { printf '  \033[32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; WARNED=1; }
fail() { printf '  \033[31m[fail]\033[0m %s\n' "$*"; FAILED=1; }
info() { printf '         %s\n' "$*"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$*"; }

WARNED=0
FAILED=0
TMP=

cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# ---------------------------------------------------------------- this machine

head2 "This machine"

dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null || echo "?"; }
VENDOR=$(dmi sys_vendor)
MODEL=$(dmi product_name)
BIOS=$(dmi bios_version)
KVER=$(uname -r)

info "Vendor : $VENDOR"
info "Model  : $MODEL"
info "BIOS   : $BIOS"
info "Kernel : $KVER"

case "$VENDOR" in
  *ASUS*|*ASUSTeK*) ;;
  \?) warn "no DMI info -- can't tell what this is" ;;
  *) warn "not an ASUS machine; PWKB is an ASUS EC thing, this is very unlikely to apply" ;;
esac

# ------------------------------------------------------------------- the table

head2 "ACPI table"

command -v iasl >/dev/null 2>&1 || {
  fail "iasl not found -- install acpica-tools and re-run"
  exit 1
}

TMP=$(mktemp -d)
DSDT=${1:-}

if [ -n "$DSDT" ]; then
  [ -r "$DSDT" ] || { fail "can't read $DSDT"; exit 1; }
  info "Using DSDT from $DSDT"
  cp "$DSDT" "$TMP/dsdt.dat" || exit 1
else
  command -v acpidump >/dev/null 2>&1 || { fail "acpidump not found -- install acpica-tools"; exit 1; }
  if [ "$(id -u)" -ne 0 ]; then
    fail "dumping the DSDT needs root -- re-run with sudo, or pass a DSDT file"
    exit 1
  fi
  acpidump -b -n DSDT -o "$TMP/dsdt.dat" >/dev/null 2>&1 || { fail "acpidump failed"; exit 1; }
  info "Dumped DSDT from firmware ($(stat -c%s "$TMP/dsdt.dat") bytes)"
fi

( cd "$TMP" && iasl -d dsdt.dat ) >"$TMP/iasl.log" 2>&1
[ -r "$TMP/dsdt.dsl" ] || { fail "iasl could not disassemble that file -- is it really a raw DSDT dump?"; exit 1; }

# Resolve the full ACPI path of PWKB by tracking the enclosing Scope/Device
# names -- iasl indents 4 spaces per nesting level, so indentation is the depth.
eval "$(awk '
  function norm(p) { sub(/^\.+/, "", p); if (p !~ /^\\/) p = "\\" p; return p }
  { match($0, /^ */); d = int(RLENGTH / 4) }
  /^ *(Scope|Device|Method|PowerResource|ThermalZone|Processor) *\(/ {
      s = $0
      sub(/^ *[A-Za-z]+ *\( */, "", s); sub(/[,)].*$/, "", s); gsub(/ +$/, "", s)
      stack[d] = s
      path = ""
      for (i = 0; i < d; i++) if (stack[i] != "") {
          if (stack[i] ~ /^\\/) path = stack[i]; else path = path "." stack[i]
      }
      if (s == "SLKB" && slkb == "") slkb = norm(path)
      if (s == "GLKB" && glkb == "") glkb = norm(path)
      next
  }
  /^ *Name *\( *PWKB *,/ && pwkb == "" {
      path = ""
      for (i = 0; i < d; i++) if (stack[i] != "") {
          if (stack[i] ~ /^\\/) path = stack[i]; else path = path "." stack[i]
      }
      pwkb = norm(path)
      if (match($0, /Buffer *\( *0x[0-9A-Fa-f]+/))
          len = strtonum(substr($0, RSTART + 8, RLENGTH - 8))
      grab = 1; next
  }
  grab {
      line = $0; sub(/\/\/.*$/, "", line)
      n = split(line, tok, /[^0-9A-Fa-fxX]+/)
      for (i = 1; i <= n; i++) if (tok[i] ~ /^0[xX][0-9A-Fa-f]+$/) bytes = bytes tok[i] " "
      if ($0 ~ /\}\)/) grab = 0
  }
  END {
      printf "PWKB_PATH=\"%s\"\n", (pwkb == "" ? "" : pwkb)
      printf "PWKB_LEN=\"%s\"\n",  (len  == "" ? 0  : len)
      printf "SLKB_PATH=\"%s\"\n", (slkb == "" ? "" : slkb)
      printf "GLKB_PATH=\"%s\"\n", (glkb == "" ? "" : glkb)
      sub(/ $/, "", bytes)
      printf "PWKB_BYTES=\"%s\"\n", bytes
  }
' "$TMP/dsdt.dsl")"

if [ -z "$PWKB_PATH" ]; then
  fail "no Name (PWKB, Buffer(...)) in your DSDT -- this module cannot work here"
  info "Your firmware stores the backlight duty levels somewhere else, or not at all."
  echo
  echo "Verdict: NOT COMPATIBLE"
  exit 1
fi

ok "found PWKB at ${PWKB_PATH}.PWKB"

if [ "$PWKB_LEN" -eq 4 ]; then
  ok "PWKB is a Buffer(4): $PWKB_BYTES"
else
  fail "PWKB is a Buffer($PWKB_LEN), not Buffer(4) -- the module hardcodes 4 bytes"
  info "Adjust PWKB_LEN in asus_kbd_pwkb.c and the duty[] array to match."
fi

if [ -n "$SLKB_PATH" ]; then
  ok "found SLKB at ${SLKB_PATH}.SLKB"
  [ "$SLKB_PATH" = "$PWKB_PATH" ] || warn "SLKB lives in a different scope than PWKB -- unusual, inspect the DSDT"
else
  fail "no SLKB method -- nothing would apply the new duty values"
fi

if [ -n "$GLKB_PATH" ]; then
  ok "found GLKB at ${GLKB_PATH}.GLKB"
else
  warn "no GLKB method -- load with relevel=0..3 instead of the default relevel=-1"
fi

if [ "$PWKB_PATH" = "$DEFAULT_EC_PATH" ]; then
  ok "path matches the module default -- no source edit needed"
else
  warn "your EC path is $PWKB_PATH, the module ships with $DEFAULT_EC_PATH"
  info "Edit EC_PATH in asus_kbd_pwkb.c and both paths in kpws.asl, then: make aml"
fi

# ------------------------------------------------------------------ the levels

head2 "What you'd gain"

if [ "$PWKB_LEN" -eq 4 ]; then
  i=0
  for b in $PWKB_BYTES; do
    pct=$(awk -v v="$((b))" 'BEGIN { printf "%.1f", v * 100 / 255 }')
    printf '         level %d: %s (%s%%)\n' "$i" "$b" "$pct"
    i=$((i + 1))
  done
  lvl1=$(echo "$PWKB_BYTES" | awk '{print $2}')
  if [ -n "$lvl1" ] && [ "$((lvl1))" -gt 40 ]; then
    ok "level 1 is $lvl1 -- bright enough to be worth dimming, same problem this module fixes"
  else
    warn "level 1 is already $lvl1 (low) -- your firmware may not have the glaring-dim-level problem"
  fi
fi

# ------------------------------------------------------------- loading it live

head2 "Loading the module"

if [ -r /sys/kernel/security/lockdown ]; then
  LD=$(sed -n 's/.*\[\(.*\)\].*/\1/p' /sys/kernel/security/lockdown)
  case "$LD" in
    none|integrity) ok "kernel lockdown = $LD (this module works)" ;;
    confidentiality) fail "kernel lockdown = confidentiality -- acpi_evaluate_object paths may be restricted" ;;
  esac
else
  ok "kernel lockdown not enabled"
fi

if command -v mokutil >/dev/null 2>&1; then
  SB=$(mokutil --sb-state 2>/dev/null | head -1)
  case "$SB" in
    *enabled*) ok "$SB -- you will need to enroll a MOK (see README step 1-3)" ;;
    *) ok "${SB:-SecureBoot disabled} -- no module signing needed" ;;
  esac
fi

[ -d "/lib/modules/$KVER/build" ] \
  && ok "kernel headers present for $KVER" \
  || warn "no kernel headers for $KVER -- install kernel-devel / linux-headers before building"

command -v dkms >/dev/null 2>&1 && ok "dkms present" || warn "dkms not installed"

SLKB_REPORT="${SLKB_PATH:+${SLKB_PATH}.SLKB}"; SLKB_REPORT="${SLKB_REPORT:-MISSING}"
GLKB_REPORT="${GLKB_PATH:+${GLKB_PATH}.GLKB}"; GLKB_REPORT="${GLKB_REPORT:-MISSING}"

# ---------------------------------------------------------------------- report

head2 "Verdict"

if [ "$FAILED" -ne 0 ]; then
  echo "  NOT COMPATIBLE as shipped -- see the [fail] lines above."
elif [ "$WARNED" -ne 0 ]; then
  echo "  LIKELY COMPATIBLE, with the adjustments in the [warn] lines above."
else
  echo "  COMPATIBLE -- follow the README as written."
fi

cat <<EOF

Paste this into an issue if you want it added to the tested-hardware table
(or if it didn't work):

    Model   : $VENDOR $MODEL
    BIOS    : $BIOS
    Kernel  : $KVER
    PWKB    : ${PWKB_PATH}.PWKB = Buffer($PWKB_LEN) { $PWKB_BYTES }
    SLKB    : $SLKB_REPORT
    GLKB    : $GLKB_REPORT

Nothing here changes your system -- this script only reads.
EOF

exit 0
