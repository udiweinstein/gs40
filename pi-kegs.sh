#!/bin/sh
# Raspberry Pi OS Lite: update KEGS from GitHub (if there is a new version)
# and run it.  Install once, then just type "kegs" (or KEGS) after login:
#
#   sudo ln -sf ~/kegs/pi-kegs.sh /usr/local/bin/kegs
#   sudo ln -sf ~/kegs/pi-kegs.sh /usr/local/bin/KEGS
#
# Extra arguments are passed to gs40.  "kegs -n" skips the update.

DIR=$(dirname "$(readlink -f "$0")")
cd "$DIR" || exit 1

if [ "$1" = "-n" ]; then
	shift
else
	OLD=$(git rev-parse HEAD 2>/dev/null)
	echo "Checking for a new KEGS version..."
	if timeout 30 git pull -q --ff-only 2>/tmp/kegs-pull.err; then
		NEW=$(git rev-parse HEAD)
		if [ "$OLD" != "$NEW" ] || [ ! -x gs40 ]; then
			echo "New version - building:"
			git log --oneline "$OLD..$NEW" 2>/dev/null | head -10
			./pi-update.sh || {
				echo "Build failed."
				[ -x gs40 ] || exit 1
				echo "Running the previous version in 5 seconds..."
				sleep 5
			}
		else
			echo "Up to date."
		fi
	else
		echo "Update failed - running the current version:"
		cat /tmp/kegs-pull.err
		sleep 5
	fi
fi

if [ ! -x gs40 ]; then
	echo "gs40 is not built yet. Run: $DIR/pi-update.sh"
	exit 1
fi

# Sound: the Pi's default output is the 3.5mm jack.  If a screen that takes
#  sound is on HDMI (it lists sound formats: sad_count in its ELD file),
#  send the sound there.  Set AUDIODEV yourself to choose another output,
#  e.g.  AUDIODEV=default:CARD=Headphones kegs
if [ -z "$AUDIODEV" ]; then
	for eld in /proc/asound/vc4hdmi0/eld* /proc/asound/vc4hdmi1/eld*; do
		[ -f "$eld" ] || continue
		if grep -q 'sad_count[[:space:]]*[1-9]' "$eld"; then
			AUDIODEV="hdmi:CARD=$(basename "$(dirname "$eld")"),DEV=0"
			export AUDIODEV
			echo "Sound: $AUDIODEV"
			break
		fi
	done
fi
exec ./gs40 "$@"
