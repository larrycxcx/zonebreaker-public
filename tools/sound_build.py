"""Generates the cyberpunk skin pack's sound effects and music from the sound pack, output to skins/cyberpunk/sfx/ and skins/cyberpunk/music/.

    python tools/sound_build.py            # regenerate everything
    python tools/sound_build.py --check    # only check, without writing files

Art source: CraftPix's sound pack (art_in/default/sound/, not in the repo): 29 sound effects (44.1kHz 16bit stereo WAV) + 5 music tracks.
Many sounds in the pack have nothing to do with this game (dogs barking, crows, doors opening and closing); those that fit are processed by the `SOUNDS` table:
- **Leading silence is removed**, then **trimmed** as needed (a 30ms fade-out at the end so it does not click). The automatic gunshot is 0.88 seconds and is trimmed to 0.2,
  or a string of shots would blur together; the ultimate freeze sound is trimmed to 2 seconds, exactly the length of the freeze.
- **Pitch shifting does no audio processing**: it only changes the sample rate in the WAV header (`rate`). 0.8 = played a bit slower and lower — patrollers and turrets use the same laser sound as the player,
  set apart by lowering the pitch; the grenade bounce uses a pitched-up Bump.
- `gain` is a volume multiplier: sounds like gunfire that go off several times a second are made a bit quieter.
Events without a match in the pack (jump, stamina exhausted, enemy lying down, D spotting the player) are not output and not filled in the skin pack, falling back to the default pack's 8-bit sounds as before.

Music: MP3s copied as is (`MUSIC`). **The stage track has been replaced by our own `level.ogg`** (2026-09) and is no longer generated here,
so `MUSIC` only has the boss track left (Track Race, the tightest rhythm of them).
"""
import os
import shutil
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "sound")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk")

# Event → (source file, trimmed to how many seconds (None = no trim), sample rate multiplier, volume multiplier)
SOUNDS = {
	"player_shoot": ("Blaster laser", 0.2, 1.0, 0.55),
	"enemy_shoot": ("Blaster laser", 0.2, 0.8, 0.5),
	"turret_shoot": ("Blaster laser", 0.25, 0.62, 0.6),
	"flyer_shoot": ("Thunderbolt", 0.35, 1.0, 0.7),
	"bullet_impact": ("Bump", 0.18, 1.0, 0.6),
	"grenade_bounce": ("Bump", 0.18, 1.35, 0.7),
	"enemy_hit": ("Punch", 0.3, 1.0, 0.7),
	"enemy_death": ("Dead2", None, 1.0, 0.8),
	"player_hurt": ("Groans", None, 1.0, 0.9),
	"player_death": ("Dead1", None, 1.0, 0.9),
	"explosion": ("Explosion", None, 1.0, 0.9),
	"ultimate_start": ("Thunderbolt", 2.0, 1.0, 0.8),
	"ultimate_blast": ("Explosion2", None, 1.0, 1.0),
	"boss_appear": ("Warning_loopable", 1.7, 1.0, 0.7),
	"grenade_throw": ("flamethrower", 0.35, 1.0, 0.7),
	"weapon_switch": ("Press", 0.3, 1.0, 0.6),
	"game_over": ("Access denied", None, 1.0, 0.9),
}
# Purpose → track name in the art pack. **The stage track is not here**: it was replaced by our own `skins/cyberpunk/music/level.ogg`
# (OGG loops without a seam, while MP3 pads a little silence at each end). Adding it back would overwrite it.
# intro (the main menu track) is left out for now: Track Intro in the pack does not fit, and will be filled back in once a suitable one turns up.
# The interface is still there (`intro` in `SkinPack.MUSIC_KEYS` and `Music.play(&"intro")` in the main menu are untouched),
# so later just putting a track in the pack makes it play.
MUSIC = {"boss": "Track race"}
SILENCE = 300    # Leading samples below this amplitude (16bit) are removed as silence
FADE = 0.03      # Seconds of fade-out at the end


def read(name):
	with wave.open(os.path.join(PACK, "Sounds", name + ".wav")) as w:
		assert w.getsampwidth() == 2, "%s is not 16bit" % name
		channels, rate = w.getnchannels(), w.getframerate()
		raw = w.readframes(w.getnframes())
	samples = list(struct.unpack("<%dh" % (len(raw) // 2), raw))
	return channels, rate, samples


def process(name, seconds, rate_scale, gain):
	channels, rate, samples = read(name)
	frames = len(samples) // channels
	start = next((f for f in range(frames) if max(abs(samples[f * channels + c]) for c in range(channels)) > SILENCE), 0)
	end = frames if seconds is None else min(frames, start + int(seconds * rate))
	fade = int(FADE * rate)
	out = []
	for f in range(start, end):
		k = gain * min(1.0, (end - f) / fade) if fade > 0 else gain
		for c in range(channels):
			out.append(max(-32768, min(32767, int(samples[f * channels + c] * k))))
	return channels, int(round(rate * rate_scale)), out


def save(path, channels, rate, samples):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with wave.open(path, "wb") as w:
		w.setnchannels(channels)
		w.setsampwidth(2)
		w.setframerate(rate)
		w.writeframes(struct.pack("<%dh" % len(samples), *samples))


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(PACK):
		sys.exit("Cannot find the sound art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(PACK))
	print("Sound effects:")
	for event, (name, seconds, rate_scale, gain) in SOUNDS.items():
		channels, rate, samples = process(name, seconds, rate_scale, gain)
		if write:
			save(os.path.join(OUT, "sfx", event + ".wav"), channels, rate, samples)
		print("  sfx/%s.wav  %.2fs  ← %s" % (event, len(samples) / channels / rate, name))
	print("Music:")
	for key, name in MUSIC.items():
		if write:
			os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
			shutil.copyfile(os.path.join(PACK, "Music", "MP3", name + ".mp3"), os.path.join(OUT, "music", key + ".mp3"))
		print("  music/%s.mp3  ← %s" % (key, name))


if __name__ == "__main__":
	main()
