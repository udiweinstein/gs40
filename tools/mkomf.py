#!/usr/bin/env python3
"""Make a IIgs OMF load file (one static code segment) from two flat builds
of the same code: one at address $0000 and one at $1000.

Every 16-bit field that holds an address inside the segment differs by $10
in its high byte between the two builds; those get RELOC records.  4-byte
pointers (like the CDA header's) are given with --long OFFSET.

usage: mkomf.py at0000.bin at1000.bin OUT [--name NAME] [--long OFF ...]
"""
import struct
import sys


def main():
    args = sys.argv[1:]
    longs = []
    name = "DISKS"
    pos = []
    i = 0
    while i < len(args):
        if args[i] == "--long":
            longs.append(int(args[i + 1], 0))
            i += 2
        elif args[i] == "--name":
            name = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    a = open(pos[0], "rb").read()
    b = open(pos[1], "rb").read()
    out = pos[2]
    if len(a) != len(b):
        sys.exit("mkomf: the two builds differ in size")

    skip = set()
    relocs = []                     # (size, offset, value)
    for off in longs:
        relocs.append((4, off, struct.unpack_from("<I", a, off)[0]))
        skip.update(range(off, off + 4))
    for i in range(1, len(a)):
        if a[i] == b[i] or i in skip:
            continue
        if a[i - 1] != b[i - 1] or ((b[i] - a[i]) & 0xff) != 0x10:
            sys.exit("mkomf: byte %04x differs in an unexpected way" % i)
        relocs.append((2, i - 1, a[i - 1] | (a[i] << 8)))

    body = bytearray()
    body += b"\xf2" + struct.pack("<I", len(a)) + a     # LCONST
    for size, off, val in sorted(relocs, key=lambda r: r[1]):
        body += struct.pack("<BBBII", 0xe2, size, 0, off, val)  # RELOC
    body += b"\x00"                                     # END

    names = b"          " + name.upper().encode()[:10].ljust(10)
    hdr_len = 44
    total = hdr_len + len(names) + len(body)
    hdr = struct.pack("<IIIBBBBIHHIIBBHIHH",
                      total,        # BYTECNT
                      0,            # RESSPC
                      len(a),       # LENGTH
                      0,            # undefined
                      10,           # LABLEN
                      4,            # NUMLEN
                      2,            # VERSION
                      0x10000,      # BANKSIZE
                      0x0000,       # KIND: static code
                      0,            # undefined
                      0,            # ORG
                      0,            # ALIGN
                      0,            # NUMSEX
                      0,            # undefined
                      1,            # SEGNUM
                      0,            # ENTRY
                      hdr_len,      # DISPNAME
                      hdr_len + len(names))  # DISPDATA
    assert len(hdr) == hdr_len
    open(out, "wb").write(hdr + names + body)
    print("mkomf: %s, %d bytes of code, %d relocations"
          % (out, len(a), len(relocs)))


main()
