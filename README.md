# GS40

**GS40** is an Apple IIgs emulator for the Mac and for the Raspberry Pi 4, made for the
40th anniversary of the Apple IIgs (September 1986).

It is based on [KEGS](https://kegs.sourceforge.net/) by Kent Dickey, with additions:
Hebrew support (built-in font and keyboard, right-to-left AppleWorks 3), new Applesoft BASIC
commands (`SHGR`, `DHGR`, `SOUND` - see `src/basic_ext.c` and `basic/testext.bas`),
a Raspberry Pi 4 SD card that boots straight into the emulator (`buildroot/`),
an F4 network menu with SMB file sharing, and the original Apple II keyboard without F keys.

- Mac: `./build.sh` builds `GS40.app`
- Raspberry Pi 4 SD card: `./buildroot/build-on-mac.sh` builds `sdcard/gs40-pi4-sdcard.img`
- Raspberry Pi OS Lite: `pi-update.sh` builds `gs40`
- Disks desk accessory (Ctrl-Cmd-Esc > Disks: choose a disk image for each drive):
  `cda/build.sh` builds `cda/DISKS` (needs cc65: `brew install cc65`); copy it into
  `SYSTEM/DESK.ACCS` on the GS/OS boot disk

GS40 is released under the GNU GPL v3, like KEGS (see `LICENSE`).

## About KEGS

KEGS is an Apple IIgs emulator for Mac, Linux, and Windows.

You must provide a ROM file (supports just about any known format, ROM01 or ROM03), and bootable image.  The directions provide details on what you need.

Press F4 while it is running to change options.

KEGS is likely the fastest IIgs emulator, hitting over 1GHz on Mac M1 systems.  It has many features, such as the ability to mount disk images directly from .zip files.

Binaries and other files are at:  https://kegs.sourceforge.net/
