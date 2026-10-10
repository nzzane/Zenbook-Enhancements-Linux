// SPDX-License-Identifier: GPL-2.0
/*
 * asus_kbd_pwkb - rewrite the firmware's keyboard-backlight PWM duty table
 *                 \_SB.PC00.LPCB.EC0.PWKB at runtime, from a MOK-signed
 *                 out-of-tree module, with Secure Boot and kernel lockdown
 *                 (integrity) left enabled.
 *
 * This is the runtime equivalent of the one-byte DSDT patch (PWKB[1]:
 * 0x55 -> 0x0A) but WITHOUT overriding any ACPI table, so it is not blocked
 * by LOCKDOWN_ACPI_TABLES.  Because it changes the data the *firmware's own*
 * SLKB method reads, every existing path keeps working and keeps the new
 * value: asus-wmi hotkeys, /sys/class/leds/asus::kbd_backlight/brightness,
 * asus_hotk_resume(), hid-asus listener registration -- all of them end up in
 * SLKB, which now indexes our table.
 *
 * How it works, using only exported ACPICA APIs that carry no lockdown hook:
 *   1. acpi_evaluate_object() on the PWKB Name node -> read + save the
 *      original 4-byte buffer.
 *   2. acpi_load_table() with a 89-byte SSDT that contains exactly one
 *      DefMethod, \_SB.PC00.LPCB.EC0.KPWS(Arg0), whose body is
 *          CopyObject (Arg0, \_SB.PC00.LPCB.EC0.PWKB)
 *          Return (Zero)
 *      This goes through the normal table loader (same path as the
 *      configfs/acpi table loader), not acpi_install_method(): since
 *      ACPICA 20260408 (Linux 7.2) acpi_install_method() fails with
 *      AE_BAD_PARAMETER because it never initialises parser_state.aml_end,
 *      which the new parser bounds checks read.  acpi_load_table() also has
 *      an unload counterpart, so rmmod leaves no trace in the namespace.
 *   3. acpi_evaluate_object() on KPWS with a Buffer argument -> AML CopyObject
 *      replaces the named PWKB object with our values.
 *   4. Re-issue SLKB(0x80 | level) so the change takes effect immediately.
 *
 * Module unload restores the saved original table and unloads the SSDT.
 *
 * More levels: SLKB indexes PWKB with the full 7-bit level (Arg0 & 0x7F), so
 * the table can be longer than the stock 4 entries. duty= takes 2-16 values
 * and the table written to the firmware is padded to 128 entries with the
 * last value, so no level the WMI interface can send ever indexes past the
 * end. asus-wmi itself stops at level 3 unless it is built with the
 * kbd_max_brightness parameter (see asus-wmi-levels/).
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/acpi.h>

#include "kpws_aml.h"		/* static u8 kpws_ssdt_aml[] */

#define EC_PATH		"\\_SB.PC00.LPCB.EC0"
#define PWKB_PATH	EC_PATH ".PWKB"
#define SLKB_PATH	EC_PATH ".SLKB"
#define GLKB_PATH	EC_PATH ".GLKB"
#define KPWS_PATH	EC_PATH ".KPWS"
#define PWKB_ORIG_LEN	4	/* stock firmware: Buffer (0x04) */
#define DUTY_MAX	16	/* most levels accepted in duty= */
#define PWKB_LEN	128	/* SLKB indexes with Arg0 & 0x7F */

static unsigned char duty[DUTY_MAX] = { 0x00, 0x0A, 0xAA, 0xFF };
static int duty_count = 4;
module_param_array(duty, byte, &duty_count, 0444);
MODULE_PARM_DESC(duty, "2-16 PWM duty bytes, one per backlight level starting at 0 (default 0,10,170,255)");

static int relevel = -1;
module_param(relevel, int, 0444);
MODULE_PARM_DESC(relevel, "Backlight level to re-apply after patching; -1 (default) = read the current level from firmware, -2 = skip");

static u8 orig_pwkb[PWKB_ORIG_LEN];
static u8 table[PWKB_LEN];
static bool have_orig;
static u32 kpws_table_idx;
static bool kpws_loaded;

static int pwkb_read(u8 out[PWKB_ORIG_LEN])
{
	struct acpi_buffer ret = { ACPI_ALLOCATE_BUFFER, NULL };
	union acpi_object *obj;
	acpi_status status;

	status = acpi_evaluate_object(NULL, (acpi_string)PWKB_PATH, NULL, &ret);
	if (ACPI_FAILURE(status)) {
		pr_err("asus_kbd_pwkb: read %s failed: %s\n", PWKB_PATH,
		       acpi_format_exception(status));
		return -ENODEV;
	}
	obj = ret.pointer;
	if (!obj || obj->type != ACPI_TYPE_BUFFER || obj->buffer.length != PWKB_ORIG_LEN) {
		pr_err("asus_kbd_pwkb: %s is not a Buffer(4)\n", PWKB_PATH);
		kfree(ret.pointer);
		return -ENODEV;
	}
	memcpy(out, obj->buffer.pointer, PWKB_ORIG_LEN);
	kfree(ret.pointer);
	return 0;
}

static int pwkb_write(const u8 *in, u32 len)
{
	union acpi_object arg;
	struct acpi_object_list list = { .count = 1, .pointer = &arg };
	acpi_status status;

	arg.type = ACPI_TYPE_BUFFER;
	arg.buffer.length = len;
	arg.buffer.pointer = (u8 *)in;

	status = acpi_evaluate_object(NULL, (acpi_string)KPWS_PATH, &list, NULL);
	if (ACPI_FAILURE(status)) {
		pr_err("asus_kbd_pwkb: %s failed: %s\n", KPWS_PATH,
		       acpi_format_exception(status));
		return -EIO;
	}
	return 0;
}

/*
 * Current level, straight from the firmware.  GLKB(2) returns KBLV, which SLKB
 * is the only writer of -- so this is exactly what the backlight is set to now.
 * Avoids yanking the light to a hardcoded level at insmod time.
 */
static int glkb_current(void)
{
	union acpi_object arg = { .type = ACPI_TYPE_INTEGER, .integer.value = 2 };
	struct acpi_object_list list = { .count = 1, .pointer = &arg };
	unsigned long long val;
	acpi_status status;

	status = acpi_evaluate_integer(NULL, (acpi_string)GLKB_PATH, &list, &val);
	if (ACPI_FAILURE(status))
		return -1;
	return (int)(val & 0x7F);
}

/* Make the new table visible right away: firmware SLKB re-reads PWKB. */
static void slkb_reissue(int level, int levels)
{
	union acpi_object arg;
	struct acpi_object_list list = { .count = 1, .pointer = &arg };

	if (level == -1)
		level = glkb_current();
	if (level < 0)
		return;
	if (level >= levels)
		level = levels - 1;
	arg.type = ACPI_TYPE_INTEGER;
	arg.integer.value = 0x80 | level;
	acpi_evaluate_object(NULL, (acpi_string)SLKB_PATH, &list, NULL);
}

static int __init pwkb_init(void)
{
	acpi_status status;
	int ret, i;

	if (duty_count < 2) {
		pr_err("asus_kbd_pwkb: duty= needs 2 to %d bytes\n", DUTY_MAX);
		return -EINVAL;
	}
	for (i = 0; i < PWKB_LEN; i++)
		table[i] = duty[min(i, duty_count - 1)];

	ret = pwkb_read(orig_pwkb);
	if (ret)
		return ret;
	have_orig = true;
	pr_info("asus_kbd_pwkb: original PWKB = %*ph\n", PWKB_ORIG_LEN, orig_pwkb);

	status = acpi_load_table((struct acpi_table_header *)kpws_ssdt_aml,
				 &kpws_table_idx);
	if (ACPI_FAILURE(status)) {
		pr_err("asus_kbd_pwkb: acpi_load_table(%s) failed: %s\n",
		       KPWS_PATH, acpi_format_exception(status));
		return -EIO;
	}
	kpws_loaded = true;

	ret = pwkb_write(table, PWKB_LEN);
	if (ret) {
		pr_warn("asus_kbd_pwkb: PWKB unchanged, unloading %s\n", KPWS_PATH);
		acpi_unload_table(kpws_table_idx);
		kpws_loaded = false;
		return ret;
	}

	slkb_reissue(relevel, duty_count);
	pr_info("asus_kbd_pwkb: PWKB now %d levels: %*ph\n", duty_count,
		duty_count, (u8 *)duty);
	return 0;
}

static void __exit pwkb_exit(void)
{
	if (have_orig) {
		pwkb_write(orig_pwkb, PWKB_ORIG_LEN);
		slkb_reissue(relevel, PWKB_ORIG_LEN);
	}
	if (kpws_loaded)
		acpi_unload_table(kpws_table_idx);
}

module_init(pwkb_init);
module_exit(pwkb_exit);
MODULE_DESCRIPTION("Rewrite ASUS EC keyboard-backlight PWM duty table (PWKB) at runtime");
MODULE_LICENSE("GPL");
MODULE_VERSION("0.3");
