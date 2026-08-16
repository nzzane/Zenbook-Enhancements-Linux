import struct, sys
src = open(sys.argv[1],'rb').read()
HDR = 36
body = src[HDR:]
# iasl emits External() decls inside an If(Zero){...} block; skip leading If(0) blocks
i = 0
while i < len(body) and body[i] == 0xA0:          # AML_IF_OP
    # decode PkgLength starting at i+1
    b0 = body[i+1]
    nbytes = b0 >> 6
    if nbytes == 0:
        pkglen = b0 & 0x3F
    else:
        pkglen = (b0 & 0x0F)
        for k in range(nbytes):
            pkglen |= body[i+2+k] << (4 + 8*k)
    i = i + 1 + pkglen
    # only skip if the predicate right after pkglen was ZeroOp (0x00)
body = body[i:]
assert body[0] == 0x14, "first opcode is 0x%02x, expected 0x14 (MethodOp)" % body[0]
hdr = bytearray(src[:HDR])
tbl = bytearray(hdr + body)
struct.pack_into('<I', tbl, 4, len(tbl))
tbl[9] = 0
tbl[9] = (-sum(tbl)) & 0xFF
open(sys.argv[2],'wb').write(bytes(tbl))
print("wrote %s: %d bytes, first body opcode 0x%02x, checksum ok=%s" %
      (sys.argv[2], len(tbl), tbl[HDR], (sum(tbl) & 0xFF) == 0))
