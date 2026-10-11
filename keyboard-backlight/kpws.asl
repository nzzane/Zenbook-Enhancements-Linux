/*
 * Helper method loaded at runtime via acpi_load_table().
 * Its only job: CopyObject a caller-supplied Buffer onto the firmware's
 * keyboard-backlight PWM duty table \_SB.PC00.LPCB.EC0.PWKB.
 *
 * Regenerate kpws_aml.h with:  make aml
 */
DefinitionBlock ("", "SSDT", 2, "KBDPWM", "PWKBSET", 0x00000001)
{
    External (\_SB.PC00.LPCB.EC0.PWKB, BuffObj)

    Method (\_SB.PC00.LPCB.EC0.KPWS, 1, NotSerialized)
    {
        CopyObject (Arg0, \_SB.PC00.LPCB.EC0.PWKB)
        Return (Zero)
    }
}
