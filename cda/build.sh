#!/bin/bash
# Build the Disks desk accessory (CDA) for GS40.
#  Needs ca65/ld65 from cc65 (Mac: brew install cc65) and python3.
#  Output: cda/DISKS (OMF, ProDOS type $B9) and cda/DISKS#b90000 (the
#  same file, named so CiderPress II and similar tools set the type).
#  It also writes src/disks_cda.h, so the next GS40 build has Disks built
#  in (Ctrl-Cmd-Esc, also under ProDOS 8).  For a real IIgs or another
#  emulator: copy DISKS#b90000 into SYSTEM/DESK.ACCS on the GS/OS disk.
set -e
cd "$(dirname "$0")"
mkdir -p build
ca65 --cpu 65816 -o build/disks.o disks.s
ld65 -C disks.cfg -S 0x0000 -o build/disks0.bin build/disks.o
ld65 -C disks.cfg -S 0x1000 -o build/disks1.bin build/disks.o
python3 ../tools/mkomf.py build/disks0.bin build/disks1.bin DISKS \
	--name DISKS --long 6 --long 10 --cheader ../src/disks_cda.h
cp DISKS 'DISKS#b90000'
echo "Built: $(pwd)/DISKS  (ProDOS type \$B9, aux \$0000)"
echo "Built into GS40 too (src/disks_cda.h): now run ./build.sh to rebuild GS40"
