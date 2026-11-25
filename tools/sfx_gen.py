"""Synthesises retro 8-bit sound effects in code (the same idea as sfxr/bfxr), output to the default pack's skins/default/sfx/*.wav.

Standard library only. Each sound is a set of parameters in SOUNDS: one or more "voices" layered together,
each with a waveform, pitch slide, vibrato, volume envelope, duty cycle and so on. To tweak a sound, change the numbers here and run:

    python tools/sfx_gen.py            # generate everything
    python tools/sfx_gen.py jump       # only generate those with jump in the name

File names match the game's event names (player_shoot, enemy_death…), and the mapping is written in skins/default/default_skin.tres.
These are placeholder sounds: replace the files of the same name with real assets, or make a new skin pack (see "Skins and art packs" in CLAUDE.md).
"""

import math
import os
import random
import struct
import sys
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skins", "default", "sfx")

# Note name → frequency (A4 = 440Hz), for writing melodies.
NOTE = {
    name + str(octave): 440.0 * 2 ** ((i - 9) / 12 + (octave - 4))
    for octave in range(1, 8)
    for i, name in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])
}


def voice(
    wave_type="square",      # square / triangle / saw / sine / noise
    freq=440.0,              # Start frequency
    freq_end=None,           # End frequency (None = no slide), sliding along an exponential curve, which sounds more natural
    duration=0.2,            # Total length of this voice (seconds)
    attack=0.0,              # Fade in
    decay=None,              # Time from the end of the attack until it fades out, using all the remaining length by default
    duty=0.5,                # Square wave duty cycle: 0.5 round, 0.125 thin and sharp
    duty_end=None,
    vibrato_depth=0.0,       # Vibrato depth (relative to frequency, 0.05 = ±5%)
    vibrato_speed=0.0,       # Vibrato speed (Hz)
    notes=None,              # Arpeggio / melody: [(start second, frequency), ...], overrides freq
    volume=1.0,
    offset=0.0,              # At which second this voice starts within the whole sound
    crush=4,                 # Hold the same value for every crush samples, imitating the grain of a low sample rate (1 = no reduction)
    seed=1,
):
    return dict(locals())


def render_voice(v):
    rng = random.Random(v["seed"])
    n = int(v["duration"] * SAMPLE_RATE)
    decay = v["decay"] if v["decay"] is not None else v["duration"] - v["attack"]
    out = [0.0] * n
    phase = 0.0
    noise_value = rng.uniform(-1, 1)
    held = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        k = t / v["duration"]

        if v["notes"]:
            f = v["notes"][0][1]
            for start, note_freq in v["notes"]:
                if t >= start:
                    f = note_freq
        elif v["freq_end"] is not None:
            f = v["freq"] * (v["freq_end"] / v["freq"]) ** k
        else:
            f = v["freq"]
        if v["vibrato_depth"]:
            f *= 1.0 + v["vibrato_depth"] * math.sin(2 * math.pi * v["vibrato_speed"] * t)

        prev_phase = phase
        phase = (phase + f / SAMPLE_RATE) % 1.0
        duty = v["duty"] if v["duty_end"] is None else v["duty"] + (v["duty_end"] - v["duty"]) * k

        w = v["wave_type"]
        if w == "square":
            s = 1.0 if phase < duty else -1.0
        elif w == "triangle":
            s = 4.0 * abs(phase - 0.5) - 1.0
        elif w == "saw":
            s = 2.0 * phase - 1.0
        elif w == "sine":
            s = math.sin(2 * math.pi * phase)
        else:  # noise: a new random value each period; the higher the frequency the more 'hiss', the lower the more "rumble" (like the NES noise channel)
            if phase < prev_phase:
                noise_value = rng.uniform(-1, 1)
            s = noise_value

        if t < v["attack"]:
            env = t / v["attack"]
        else:
            env = max(0.0, 1.0 - (t - v["attack"]) / decay) if decay > 0 else 0.0
            env = env * env  # Square decay, more like a hit than linear

        if i % v["crush"] == 0:
            held = s * env * v["volume"]
        out[i] = held
    return out


def render(layers, peak=0.8):
    length = max(int((l["offset"] + l["duration"]) * SAMPLE_RATE) for l in layers)
    mix = [0.0] * length
    for layer in layers:
        start = int(layer["offset"] * SAMPLE_RATE)
        for i, s in enumerate(render_voice(layer)):
            mix[start + i] += s
    loudest = max(abs(s) for s in mix) or 1.0
    scale = peak / loudest
    # A 5ms fade-out at the end, to avoid a 'click' where it is cut
    fade = int(0.005 * SAMPLE_RATE)
    for i in range(fade):
        mix[length - 1 - i] *= i / fade
    return [s * scale for s in mix]


def write_wav(path, samples):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def shoot_variant(base, seed):
    return [
        voice("square", freq=base, freq_end=base * 0.25, duration=0.12, duty=0.25, duty_end=0.5, seed=seed),
        voice("noise", freq=6000, duration=0.035, volume=0.35, seed=seed),
    ]


# Event name → (description, voices, peak volume). Peaks are set by "how often it is heard": frequent sounds like shots and hits are a bit quieter.
SOUNDS = {
    # ---- Required ----
    "player_shoot_1": ("Player shot (variant 1, three played in turn)", shoot_variant(1150, 11), 0.55),
    "player_shoot_2": ("Player shot (variant 2)", shoot_variant(1250, 12), 0.55),
    "player_shoot_3": ("Player shot (variant 3)", shoot_variant(1330, 13), 0.55),
    "jump": ("Jump: a short rise", [
        voice("square", freq=280, freq_end=720, duration=0.16, duty=0.5, duty_end=0.25),
    ], 0.6),
    "player_hurt": ("Player hurt: a trembling drop", [
        voice("square", freq=620, freq_end=180, duration=0.28, duty=0.5, vibrato_depth=0.25, vibrato_speed=35),
        voice("noise", freq=3000, duration=0.08, volume=0.5, seed=3),
    ], 0.75),
    "menu_move": ("Menu cursor move: a soft 'beep'", [
        voice("square", freq=880, duration=0.045, duty=0.25, volume=0.8),
    ], 0.35),
    "menu_select": ("Menu confirm: two rising notes", [
        voice("square", duration=0.14, duty=0.5, decay=0.3,
              notes=[(0.0, NOTE["E5"]), (0.06, NOTE["A5"])]),
    ], 0.5),
    "menu_back": ("Menu back: two falling notes", [
        voice("square", duration=0.14, duty=0.25, decay=0.3,
              notes=[(0.0, NOTE["A4"]), (0.06, NOTE["E4"])]),
    ], 0.45),
    "player_down": ("Player down waiting for revival (co-op): a sinking drop, ending on a tail that says there is still hope", [
        voice("square", freq=520, freq_end=150, duration=0.3, duty=0.25, vibrato_depth=0.15, vibrato_speed=14),
        voice("square", freq=190, freq_end=240, duration=0.22, duty=0.5, volume=0.45, offset=0.3),
    ], 0.7),
    "player_revive": ("Revived by a partner: three notes flicking up", [
        voice("square", duration=0.3, duty=0.5, decay=0.4,
              notes=[(0.0, NOTE["D4"]), (0.08, NOTE["A4"]), (0.16, NOTE["D5"])]),
    ], 0.65),
    "player_death": ("Player death: a falling arpeggio, then a long slide down", [
        voice("square", duration=0.36, duty=0.5, decay=0.5,
              notes=[(0.0, NOTE["C5"]), (0.09, NOTE["A4"]), (0.18, NOTE["F4"]), (0.27, NOTE["D4"])]),
        voice("square", freq=NOTE["D4"], freq_end=55, duration=0.9, duty=0.25, offset=0.36,
              vibrato_depth=0.08, vibrato_speed=8),
    ], 0.75),
    "enemy_shoot": ("Enemy shot (shared by patrollers A/B/C): lower and thinner than the player's gun", [
        voice("square", freq=720, freq_end=190, duration=0.14, duty=0.125),
        voice("noise", freq=4000, duration=0.03, volume=0.3, seed=5),
    ], 0.5),
    "enemy_hit": ("Enemy hit: a short 'tick'", [
        voice("noise", freq=5000, duration=0.05, volume=0.8, seed=6),
        voice("square", freq=950, freq_end=600, duration=0.05, duty=0.5, volume=0.6),
    ], 0.55),
    "enemy_death": ("Enemy death: a small explosion", [
        voice("noise", freq=2400, freq_end=180, duration=0.38, seed=7),
        voice("square", freq=420, freq_end=70, duration=0.3, duty=0.5, volume=0.5),
    ], 0.75),
    "bullet_impact": ("Bullet hitting a wall / the ground: a soft 'hiss'", [
        voice("noise", freq=8000, freq_end=3000, duration=0.06, seed=8),
    ], 0.3),
    "game_over": ("Game over: three falling notes + a long tail", [
        voice("square", duration=0.66, duty=0.5, decay=0.8,
              notes=[(0.0, NOTE["G4"]), (0.22, NOTE["E4"]), (0.44, NOTE["C4"])]),
        voice("triangle", freq=NOTE["C3"], freq_end=NOTE["G2"], duration=0.7, offset=0.66,
              vibrato_depth=0.03, vibrato_speed=6, volume=1.2),
    ], 0.7),
    "level_clear": ("Stage clear: three rising notes + a bright long note", [
        voice("square", duration=0.66, duty=0.5, decay=0.6,
              notes=[(0.0, NOTE["C4"]), (0.18, NOTE["E4"]), (0.36, NOTE["G4"])]),
        voice("square", freq=NOTE["C5"], duration=0.8, offset=0.54, duty=0.25,
              vibrato_depth=0.02, vibrato_speed=7, volume=1.1),
        voice("triangle", freq=NOTE["C3"], duration=0.9, offset=0.54, volume=0.8),
    ], 0.7),
    # ---- Suggested ----
    "chaser_alert": ("D Player spotted: two quick rising 'beep beep!'", [
        voice("square", freq=NOTE["A5"], duration=0.07, duty=0.5),
        voice("square", freq=NOTE["E6"], duration=0.1, duty=0.5, offset=0.09),
    ], 0.6),
    "enemy_prone": ("Enemy lying down: a low 'thud' + rustling cloth", [
        voice("triangle", freq=230, freq_end=100, duration=0.12, crush=2),
        voice("noise", freq=1500, duration=0.04, volume=0.4, seed=9),
    ], 0.6),
    "turret_shoot": ("Turret fire: a heavier, duller cannon sound", [
        voice("square", freq=420, freq_end=75, duration=0.24, duty=0.5),
        voice("noise", freq=1800, freq_end=300, duration=0.16, volume=0.7, seed=10),
    ], 0.65),
    "flyer_shoot": ("E Firing downward: a pitch falling from high", [
        voice("triangle", freq=1500, freq_end=380, duration=0.2, vibrato_depth=0.06, vibrato_speed=30, crush=2),
    ], 0.55),
    # ---- Grenades ----
    "grenade_throw": ("Grenade thrown: a short 'whoosh'", [
        voice("noise", freq=900, freq_end=3500, duration=0.14, attack=0.03, volume=0.7, seed=12),
        voice("triangle", freq=300, freq_end=520, duration=0.08, crush=2, volume=0.5),
    ], 0.4),
    "grenade_bounce": ("Grenade bouncing on landing: a crisp 'ting'", [
        voice("triangle", freq=1100, freq_end=800, duration=0.06, crush=2),
        voice("noise", freq=6000, duration=0.02, volume=0.4, seed=13),
    ], 0.45),
    "explosion": ("Grenade explosion: bigger and longer than an enemy death", [
        voice("noise", freq=1600, freq_end=90, duration=0.65, seed=14),
        voice("square", freq=220, freq_end=40, duration=0.5, duty=0.5, volume=0.6),
        voice("noise", freq=5000, freq_end=1500, duration=0.08, volume=0.6, seed=15),
    ], 0.85),
    "weapon_switch": ("Weapon switch: a short 'click'", [
        voice("square", freq=1400, freq_end=1800, duration=0.035, duty=0.25),
        voice("square", freq=900, duration=0.04, duty=0.25, offset=0.045),
        voice("noise", freq=7000, duration=0.015, volume=0.5, seed=16),
    ], 0.4),
    # ---- Boss ----
    "hammer_smash": ("Hammer slam: one dull metal impact + gravel kicked up", [
        voice("square", freq=150, freq_end=48, duration=0.26, duty=0.5, volume=0.95),
        voice("noise", freq=1400, freq_end=260, duration=0.22, volume=0.6, seed=31),
        voice("triangle", freq=70, freq_end=38, duration=0.34, attack=0.01, volume=0.8),
    ], 0.9),
    "boss_enrage": ("Boss Entering phase two: an alarm climbing all the way up + a low surge", [
        voice("square", duration=0.7, duty=0.3, decay=1.6, volume=0.6,
              notes=[(0.0, 330), (0.14, 392), (0.28, 494), (0.42, 587), (0.56, 740)]),
        voice("triangle", freq=48, freq_end=96, duration=0.8, attack=0.08, volume=0.95),
        voice("noise", freq=900, freq_end=3200, duration=0.5, volume=0.35, seed=32),
    ], 0.8),
    "boss_appear": ("Boss Appearance: two rounds of a high-low alarm + a low rumble", [
        voice("square", duration=0.84, duty=0.5, decay=2.0, volume=0.55,
              notes=[(0.0, 660), (0.18, 440), (0.36, 660), (0.54, 440)]),
        voice("triangle", freq=55, freq_end=45, duration=1.0, attack=0.1, volume=0.9),
    ], 0.75),
    # ---- Ultimate ----
    "ultimate_start": ("Ultimate fired: a charge-up rising higher and higher", [
        voice("square", freq=180, freq_end=1600, duration=0.9, duty=0.5, duty_end=0.125, vibrato_depth=0.04, vibrato_speed=18),
        voice("noise", freq=500, freq_end=4000, duration=0.9, attack=0.6, volume=0.35, seed=17),
    ], 0.6),
    "ultimate_blast": ("Ultimate destroying enemies: a huge, long explosion", [
        voice("noise", freq=1400, freq_end=50, duration=1.3, seed=18),
        voice("square", freq=160, freq_end=30, duration=1.1, duty=0.5, volume=0.7),
        voice("triangle", freq=90, freq_end=35, duration=1.2, volume=0.8, crush=2),
    ], 0.9),
    "stamina_exhausted": ("Stamina exhausted: two falling notes of 'tired'", [
        voice("triangle", freq=NOTE["E5"], duration=0.1, crush=2),
        voice("triangle", freq=NOTE["A4"], duration=0.16, offset=0.11, crush=2),
    ], 0.5),
}


def main():
    # When the console encoding cannot show Chinese (cp1252, say), print ? instead of crashing; GBK / UTF-8 consoles show Chinese as usual.
    sys.stdout.reconfigure(errors="replace")
    os.makedirs(OUT_DIR, exist_ok=True)
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for name, (desc, layers, peak) in SOUNDS.items():
        if only and only not in name:
            continue
        samples = render(layers, peak)
        write_wav(os.path.join(OUT_DIR, name + ".wav"), samples)
        rms = math.sqrt(sum(s * s for s in samples) / len(samples))
        print(f"{name:20s} {len(samples) / SAMPLE_RATE:5.2f}s  peak {max(abs(s) for s in samples):.2f}  rms {rms:.3f}  {desc}")


if __name__ == "__main__":
    main()
