/************************************************************************/
/*			KEGS: Apple //gs Emulator			*/
/*			Copyright 2002-2023 by Kent Dickey		*/
/*									*/
/*	This code is covered by the GNU GPL v3				*/
/*	See the file COPYING.txt or https://www.gnu.org/licenses/	*/
/*	This program is provided with no warranty			*/
/*									*/
/*	The KEGS web page is kegs.sourceforge.net			*/
/*	You may contact the author at: kadickey@alumni.princeton.edu	*/
/************************************************************************/

#ifdef SDL_AUDIO
// Ignore entire file if SDL_AUDIO is not defined!

// SDL2 sound output.  Used by the SDL2 build (sdlkegs) so it needs no
//  PulseAudio: SDL talks to ALSA directly on a minimal system (Buildroot,
//  Pi OS Lite), and to PulseAudio/PipeWire on a desktop.
// Modeled after pulseaudio_driver.c: the emulator writes stereo 16-bit
//  samples into a ring buffer, and SDL's audio thread pulls them out.

#include <SDL.h>
#include "defc.h"
#include "sound.h"


#define SDLAUDIO_REBUF_SIZE	(64*1024)	// Must be a power of 2

word32	g_sdlaudio_rebuf[SDLAUDIO_REBUF_SIZE];
volatile int g_sdlaudio_rd_pos = 0;
volatile int g_sdlaudio_wr_pos = 0;
volatile int g_sdlaudio_playing = 0;
SDL_AudioDeviceID g_sdlaudio_dev = 0;

extern int g_preferred_rate;
extern int g_sound_min_samples;
extern int g_sound_max_multiplier;

// F4 Video and Sound "Sound output" (saved in config.kegs):
//  0 Auto: whatever the start-up script chose (AUDIODEV, or ~/.asoundrc
//    on the SD card), 1 HDMI 1, 2 HDMI 2, 3 the 3.5mm jack.
//  The Raspberry Pi's ALSA card names; SDL's ALSA backend opens the device
//  named in AUDIODEV.
int	g_cfg_sound_out = 0;
static const char *g_sdlaudio_out_dev[4] = { 0, "hdmi:CARD=vc4hdmi0,DEV=0",
		"hdmi:CARD=vc4hdmi1,DEV=0", "plughw:CARD=Headphones,DEV=0" };
static const char *g_sdlaudio_out_card[4] = { 0, "vc4hdmi0", "vc4hdmi1",
							"Headphones" };
static char	*g_sdlaudio_auto_dev = 0;	// AUDIODEV when KEGS started
static int	g_sdlaudio_auto_saved = 0;

// Set AUDIODEV for the chosen output (Auto: as it was at start-up)
static void
sdlaudio_set_env()
{
	const char *dev;
	int	out;

	if(!g_sdlaudio_auto_saved) {
		dev = getenv("AUDIODEV");
		g_sdlaudio_auto_dev = dev ? kegs_malloc_str(dev) : 0;
		g_sdlaudio_auto_saved = 1;
	}
	out = g_cfg_sound_out;
	if((out < 0) || (out > 3)) {
		out = 0;
	}
	dev = out ? g_sdlaudio_out_dev[out] : g_sdlaudio_auto_dev;
	if(dev) {
		setenv("AUDIODEV", dev, 1);
	} else {
		unsetenv("AUDIODEV");
	}
	printf("SDL audio: AUDIODEV=%s\n", dev ? dev : "(not set)");
}

// Does this Pi have the ALSA sound card named card?
static int
sdlaudio_has_card(const char *card)
{
	char	line[256], name[64];
	FILE	*fp;
	int	num, found;

	fp = fopen("/proc/asound/cards", "r");
	if(!fp) {
		return 0;
	}
	found = 0;
	while(fgets(line, sizeof(line), fp)) {
		if((sscanf(line, " %d [%63[^] ]", &num, name) == 2) &&
							!strcmp(name, card)) {
			found = 1;
		}
	}
	fclose(fp);
	return found;
}

// The Sound output line changed: close the device and open it again
void
sdlaudio_change_output()
{
	if(!g_sdlaudio_dev && !SDL_WasInit(SDL_INIT_AUDIO)) {
		return;			// Sound is off (-audio 0)
	}
	sdlaudio_shutdown();
	SDL_QuitSubSystem(SDL_INIT_AUDIO);
	(void)sdlaudio_init();
}

// Status line under "Sound output" in F4
char *
cfg_sound_out_status(int get_status)
{
	char	buf[120];
	const char *dev;
	int	out;

	if(!get_status) {
		return 0;
	}
	out = g_cfg_sound_out;
	if((out < 0) || (out > 3)) {
		out = 0;
	}
	dev = getenv("AUDIODEV");
	if(out && !sdlaudio_has_card(g_sdlaudio_out_card[out])) {
		snprintf(buf, sizeof(buf), "No %s sound card on this computer",
						g_sdlaudio_out_card[out]);
	} else if(!g_sdlaudio_dev) {
		snprintf(buf, sizeof(buf), "Could not open %s",
					dev ? dev : "the default output");
	} else {
		snprintf(buf, sizeof(buf), "Playing on %s",
					dev ? dev : "the default output");
	}
	return kegs_malloc_str(buf);
}

int
sdlaudio_send_audio(byte *ptr, int in_size)
{
	word32	*wptr;
	int	samps, pos, i;

	samps = in_size / 4;
	wptr = (word32 *)ptr;
	pos = g_sdlaudio_wr_pos;
	for(i = 0; i < samps; i++) {
		g_sdlaudio_rebuf[pos] = *wptr++;
		pos = (pos + 1) & (SDLAUDIO_REBUF_SIZE - 1);
	}
	g_sdlaudio_wr_pos = pos;

	return in_size;
}

// Runs on SDL's audio thread
void
sdlaudio_callback(void *userdata, Uint8 *stream, int len)
{
	word32	*out;
	int	samps_needed, samps_avail, pos, min_samples, max_samples;
	int	num, i;

	if(userdata) {			// Avoid unused var warning
	}
	out = (word32 *)stream;
	samps_needed = len / 4;
	pos = g_sdlaudio_rd_pos;
	samps_avail = (g_sdlaudio_wr_pos - pos) & (SDLAUDIO_REBUF_SIZE - 1);
	min_samples = g_sound_min_samples;
	if(samps_needed > min_samples) {
		min_samples = samps_needed;
	}
	max_samples = min_samples * g_sound_max_multiplier;

	if(!g_sdlaudio_playing && (samps_avail > min_samples)) {
		g_sdlaudio_playing = 1;		// Enough buffered, start
	}
	if(g_sdlaudio_playing && (samps_avail > max_samples)) {
		// Too far behind: skip ahead to keep latency low
		pos = (pos + max_samples / 2) & (SDLAUDIO_REBUF_SIZE - 1);
		samps_avail -= max_samples / 2;
	}

	num = 0;
	if(g_sdlaudio_playing) {
		num = MY_MIN(samps_avail, samps_needed);
		for(i = 0; i < num; i++) {
			out[i] = g_sdlaudio_rebuf[pos];
			pos = (pos + 1) & (SDLAUDIO_REBUF_SIZE - 1);
		}
		g_sdlaudio_rd_pos = pos;
		if(num < samps_needed) {
			g_sdlaudio_playing = 0;	// Ran dry, wait to refill
		}
	}
	for(i = num; i < samps_needed; i++) {
		out[i] = 0;			// Silence
	}
}

int
sdlaudio_init()
{
	SDL_AudioSpec want, have;

	g_sdlaudio_rd_pos = 0;
	g_sdlaudio_wr_pos = 0;
	g_sdlaudio_playing = 0;

	sdlaudio_set_env();
	if(SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
		printf("SDL audio init failed: %s\n", SDL_GetError());
		return 1;
	}
	SDL_zero(want);
	want.freq = g_preferred_rate;
	want.format = AUDIO_S16LSB;
	want.channels = 2;
	want.samples = 1024;
	want.callback = sdlaudio_callback;
	g_sdlaudio_dev = SDL_OpenAudioDevice(0, 0, &want, &have,
					SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
	if(g_sdlaudio_dev == 0) {
		printf("SDL_OpenAudioDevice failed: %s\n", SDL_GetError());
		SDL_QuitSubSystem(SDL_INIT_AUDIO);
		return 1;
	}
	printf("SDL audio: driver %s, rate %d, buffer %d samples\n",
		SDL_GetCurrentAudioDriver(), have.freq, have.samples);
	sound_set_audio_rate(have.freq);
	SDL_PauseAudioDevice(g_sdlaudio_dev, 0);

	return 0;
}

void
sdlaudio_shutdown()
{
	if(g_sdlaudio_dev) {
		SDL_CloseAudioDevice(g_sdlaudio_dev);
		g_sdlaudio_dev = 0;
	}
}

#endif		/* SDL_AUDIO */
