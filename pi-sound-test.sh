#!/bin/sh
# Raspberry Pi sound test - nothing to do with KEGS itself.
#
# Plays a short test sound (pi-sound-test.wav: a note on the left, one on
# the right, then two on both) on every sound output the Pi has, each in a
# few different ways, and asks after each one whether you heard it.
# Everything is written to pi-sound-test.log next to this script, together
# with what the Pi says about its sound hardware and the screen.
#
#   ~/kegs/pi-sound-test.sh          ask "did you hear it?" after each test
#   ~/kegs/pi-sound-test.sh -a       no questions: just play and log
#   ~/kegs/pi-sound-test.sh -l       only write the log, play nothing
#
# It changes nothing on the Pi: no settings, no volume, no files except the
# log (and a temporary folder under /tmp).

DIR=$(dirname "$(readlink -f "$0")")
WAV=$DIR/pi-sound-test.wav
LOG=$DIR/pi-sound-test.log
TMP=/tmp/pi-sound-test.$$
ASK=1
PLAY=1
case "$1" in
-a)	ASK=0 ;;
-l)	ASK=0; PLAY=0 ;;
esac

mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.old"
: > "$LOG" 2>/dev/null || { LOG=/tmp/pi-sound-test.log; : > "$LOG"; }

have() { command -v "$1" >/dev/null 2>&1; }
say() { echo "$@"; echo "$@" >> "$LOG"; }		# screen and log
log() { echo "$@" >> "$LOG"; }				# log only
# Run a command, output to the log only
run() {
	log ""
	log "\$ $*"
	"$@" >> "$LOG" 2>&1
	log "[exit code $?]"
}
# Show a file in the log
show() {
	log ""
	if [ -r "$1" ]; then
		log "--- $1"
		cat "$1" >> "$LOG" 2>&1
	else
		log "--- $1: not there"
	fi
}

say "Raspberry Pi sound test - $(date)"
say "Log file: $LOG"
say ""

# ---------------------------------------------------------------------
# 1. What the Pi says about itself
# ---------------------------------------------------------------------
log "===== 1. SYSTEM ====="
log "Model: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
run uname -a
show /etc/os-release
log ""
log "User: $(id)"
case " $(id -Gn) " in
*" audio "*)	log "User is in the audio group: yes" ;;
*)		if [ "$(id -u)" = 0 ]; then
			log "Running as root"
		else
			say "NOTE: user $(id -un) is not in the 'audio' group -" \
				"sound may be refused."
			say "      Fix: sudo usermod -aG audio $(id -un)   (then log out and in)"
		fi ;;
esac

log ""
log "===== 2. BOOT SETTINGS ====="
for f in /boot/firmware/config.txt /boot/config.txt; do
	if [ -r "$f" ]; then
		log "--- $f (lines without comments)"
		grep -v '^[[:space:]]*#' "$f" | grep -v '^[[:space:]]*$' >> "$LOG"
	fi
done
show /proc/cmdline

log ""
log "===== 3. SCREEN (HDMI) ====="
for d in /sys/class/drm/card*-HDMI-A-*; do
	[ -d "$d" ] || continue
	log "$(basename "$d"): status=$(cat "$d/status" 2>/dev/null)" \
		"enabled=$(cat "$d/enabled" 2>/dev/null)" \
		"edid=$(wc -c < "$d/edid" 2>/dev/null) bytes"
done
# The ELD is what the screen told the Pi about its sound: speakers, formats
for eld in /proc/asound/vc4hdmi*/eld* /proc/asound/*HDMI*/eld*; do
	[ -f "$eld" ] && show "$eld"
done

log ""
log "===== 4. SOUND CARDS ====="
show /proc/asound/cards
show /proc/asound/pcm
show /proc/asound/modules
have aplay && run aplay -l
have aplay && run aplay -L
log ""
log "\$ lsmod | grep -E 'snd|vc4|hdmi'"
lsmod 2>/dev/null | grep -E 'snd|vc4|hdmi' >> "$LOG"
log ""
log "Sound servers running (PipeWire / PulseAudio take over the sound cards):"
ps -e 2>/dev/null | grep -E 'pipewire|pulseaudio|wireplumber' >> "$LOG" ||
	log "  none"
show "$HOME/.asoundrc"
show /etc/asound.conf
log ""
log "Environment: SDL_AUDIODRIVER=$SDL_AUDIODRIVER AUDIODEV=$AUDIODEV" \
	"ALSA_CARD=$ALSA_CARD"

# Card names: the word in [brackets] in /proc/asound/cards
CARDS=$(sed -n 's/^ *[0-9][0-9]* *\[\([^] ]*\) *\].*/\1/p' /proc/asound/cards \
								2>/dev/null)
log ""
log "===== 5. VOLUME CONTROLS ====="
if have amixer; then
	for c in $CARDS; do
		run amixer -c "$c" scontents
	done
else
	log "amixer is not installed"
fi

log ""
log "===== 6. KERNEL MESSAGES ABOUT SOUND AND HDMI ====="
(dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null) |
	grep -iE 'vc4|hdmi|snd|alsa|audio|bcm2835' | tail -n 80 >> "$LOG"

if [ -z "$CARDS" ]; then
	say "The Pi shows NO sound cards at all (see /proc/asound/cards in the log)."
fi
say "Sound cards found: $(echo $CARDS)"
for d in /sys/class/drm/card*-HDMI-A-*; do
	[ -d "$d" ] || continue
	say "  HDMI socket ${d##*-}: $(cat "$d/status" 2>/dev/null)"
done
for c in $CARDS; do
	for eld in /proc/asound/"$c"/eld*; do
		[ -f "$eld" ] || continue
		name=$(sed -n 's/^monitor_name[[:space:]]*//p' "$eld")
		sads=$(sed -n 's/^sad_count[[:space:]]*//p' "$eld")
		if [ -n "$name$sads" ]; then
			say "  $c: screen \"$name\", sound formats it lists: ${sads:-?}"
		else
			say "  $c: no screen details (ELD) from this socket"
		fi
	done
done
say ""

# ---------------------------------------------------------------------
# 2. Play the test sound in every way
# ---------------------------------------------------------------------
if [ "$PLAY" = 0 ]; then
	say "Log only (-l): nothing played."
	exit 0
fi
if ! have aplay; then
	say "aplay is not installed.  Run:  sudo apt install -y alsa-utils"
	exit 1
fi
if [ ! -f "$WAV" ]; then
	say "Test sound $WAV is missing."
	exit 1
fi

log "===== 7. PLAY TESTS ====="
N=0
SUMMARY=$TMP/summary
: > "$SUMMARY"
STOP=0

# test "what it is" DEVICE [HOME folder with its own .asoundrc]
test_play() {
	[ "$STOP" = 1 ] && return
	N=$((N + 1))
	desc=$1
	dev=$2
	home=$3
	say "Test $N: $desc"
	say "        device: $dev"
	log "\$ aplay -D $dev $(basename "$WAV")   ${home:+(HOME=$home)}"
	if [ -n "$home" ]; then
		HOME=$home timeout 20 aplay -D "$dev" "$WAV" > "$TMP/out" 2>&1
	else
		timeout 20 aplay -D "$dev" "$WAV" > "$TMP/out" 2>&1
	fi
	rc=$?
	cat "$TMP/out" >> "$LOG"
	log "[exit code $rc]"
	if [ "$rc" = 0 ]; then
		played="played"
	elif [ "$rc" = 124 ]; then
		played="STUCK (stopped after 20 s)"
	else
		played="ERROR"
		say "        aplay failed: $(grep -v '^Playing' "$TMP/out" | head -n 1)"
	fi
	heard="-"
	if [ "$ASK" = 1 ] && [ "$rc" = 0 ]; then
		while :; do
			printf "        Did you hear it? y = yes, n = no, r = play again, q = stop: "
			read -r ans || ans=q
			case "$ans" in
			y|Y)	heard="HEARD"; break ;;
			n|N)	heard="silent"; break ;;
			q|Q)	heard="(stopped)"; STOP=1; break ;;
			r|R)	if [ -n "$home" ]; then
					HOME=$home timeout 20 aplay -D "$dev" "$WAV" \
								>/dev/null 2>&1
				else
					timeout 20 aplay -D "$dev" "$WAV" >/dev/null 2>&1
				fi ;;
			esac
		done
	fi
	log "RESULT test $N: $played, answer: $heard"
	printf '%2d  %-26s %-10s %s\n' "$N" "$played" "$heard" "$desc" >> "$SUMMARY"
	say ""
}

if [ "$ASK" = 1 ]; then
	say "Each test plays 4 notes (about 2 seconds): left, right, both, both."
	say "Turn the volume of the screen / speakers up, then press Enter."
	read -r ans
fi

for c in $CARDS; do
	case "$c" in
	vc4hdmi*|*HDMI*|*hdmi*)
		test_play "HDMI ($c) - the HDMI way" "hdmi:CARD=$c,DEV=0"
		test_play "HDMI ($c) - default for this card" "default:CARD=$c"
		test_play "HDMI ($c) - plain hardware + conversion" \
							"plughw:CARD=$c,DEV=0"
		# What KEGS's SD card does (kegs-start): its own .asoundrc
		mkdir -p "$TMP/home-$c"
		printf 'pcm.!default "%s"\nctl.!default { type hw card "%s" }\n' \
			"hdmi:CARD=$c,DEV=0" "$c" > "$TMP/home-$c/.asoundrc"
		test_play "HDMI ($c) - like the KEGS SD card (.asoundrc)" \
							"default" "$TMP/home-$c"
		# The same with format conversion in front of it
		mkdir -p "$TMP/home2-$c"
		printf 'pcm.!default { type plug slave.pcm "%s" }\nctl.!default { type hw card "%s" }\n' \
			"hdmi:CARD=$c,DEV=0" "$c" > "$TMP/home2-$c/.asoundrc"
		test_play "HDMI ($c) - .asoundrc with conversion (plug)" \
							"default" "$TMP/home2-$c"
		;;
	*)
		test_play "$c (3.5mm jack if 'Headphones') - default for this card" \
							"default:CARD=$c"
		test_play "$c - plain hardware + conversion" "plughw:CARD=$c,DEV=0"
		;;
	esac
done
test_play "The Pi's own default output (what a program gets if it asks for nothing)" \
								"default"

say "===== SUMMARY ====="
say " #  played?                    heard?     test"
cat "$SUMMARY"
cat "$SUMMARY" >> "$LOG"
say ""
say "The full log is in: $LOG"
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$IP" ]; then
	say "To copy it to the Mac, type this on the Mac (Terminal):"
	say "  scp $(id -un)@$IP:$LOG ~/apple2/kegs/"
fi
