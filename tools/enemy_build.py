"""Generates the cyberpunk skin pack's enemy art from the enemy art pack, output to skins/cyberpunk/enemies/<enemy>/.

    python tools/enemy_build.py            # regenerate everything
    python tools/enemy_build.py --check    # only check whether anything is cut off by the canvas, without writing files

The source is a CraftPix enemy pack, unpacked in art_in/default/enemies/ (not in the repo: the licence forbids redistributing the source files).
The format is the same as the player art: each frame 48×48 with the feet on the bottom edge. PNG reading / writing, mirroring and anchors all reuse skin_build.py,
so enemies and the player stand on the same ground line: vertically the anchor likewise puts the feet 16px below the body origin.
**Frames are wider than the player's**: 80×56 with anchor (40, 40) — when an enemy falls it sprawls out in front, which 56 wide cannot hold,
so it needs 40px on each side (FRAME_W / FRAME_H / ANCHOR in `EnemySpriteAppearance` have to match this).

How it differs from the player:
1. **An enemy is one whole picture** (the gun is drawn on the body), with no arms to assemble, so it is **not aligned to the torso frame by frame**:
   the whole character is positioned once by the torso of the first idle frame, and every other frame keeps the artist's own placement (the bob of walking, the shift of falling are in it).
2. **One piece of art makes several enemies**: patrollers A/B/C are all number 2, told apart by recolouring the clothes (`VARIANTS`).
3. **The flying E (drone number 5) does not stand on the ground**: its hitbox (28×20) is centred on the origin, so the anchor lines up with **the centre of the body**,
   not the feet; the frame also stays at the art's original 48×48 (anchor 24, 24), enough for the lightning striking down when attacking and the drop when crashing.
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "enemies")
OWN = os.path.join(HERE, "..", "art_src")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "enemies")

CELL = sb.CELL
FRAME_W, FRAME_H = 80, 56
ANCHOR = (40, 40)

# Patroller (number 2, a punk with a gun): action name → (file, which frames to take).
# The art's attack animation is three groups of 3 frames each: level, diagonally down, diagonally up — exactly matching the patroller's aim directions.
# The art pack has no prone shooting; it was drawn by us (art_src/walker_prone.png, a row of 4 frames, frame 1 still, frame 2 with a muzzle flash).
WALKER_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
	"attack_level": ("Attack.png", [0, 1, 2]),
	"attack_down": ("Attack.png", [3, 4, 5]),
	"attack_up": ("Attack.png", [6, 7, 8]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
WALKER_PRONE = "walker_prone.png"
# The prone group is positioned separately by **the centre of the shirt**, 5px in front of the origin (the same rule as the player's prone pose):
# it was drawn lying forward inside the original 48-wide cell, and copied as is the character would jump forward a dozen pixels when lying down,
# while the prone hitbox is still centred on the origin. The four frames share the position measured from the first, and the firing frame keeps its relative motion.
PRONE_TORSO_X = 5

# Three patrollers recoloured from one set of art: the original clothes colour → the new colour (colours not listed stay unchanged).
# A keeps the original purple; B orange; C red — C has the longest range and lies down too, so it gets the most eye-catching colour.
# No green: F's art (number 1) already wears green.
SHIRT = [(0x66, 0x3b, 0x93), (0x8b, 0x72, 0xde)]
VARIANTS = {
	"1_a": {},
	"1_b": {SHIRT[0]: (0xa8, 0x4a, 0x12), SHIRT[1]: (0xf0, 0x8c, 0x2c)},
	"1_c": {SHIRT[0]: (0x8e, 0x16, 0x2a), SHIRT[1]: (0xd8, 0x3c, 0x4c)},
}


# Enemies D (number 3, the skateboarder) and F (number 1, the bat guy): one piece of art makes one enemy, actions map directly, and the whole character is positioned once by the torso of one frame.
# The key is the output action name (EnemySpriteAppearance picks by it), the value is (file, which frames to take); ANCHOR_CLIP is whose first frame is used for positioning.
# D: normally glides on the skateboard (walk); when charging it rides standing on the board (run, the art's Attack); jumps also use the first frame of the on-board group (air);
# the art has two hurt groups, and Hurt2 is the one standing on the board — D is almost always on it. Idle is standing with the board in hand, only seen when stuck.
# F: throwing a grenade = batting it out with the bat. The first 3 frames of the art's Attack are wind-up (almost the same as idle), and frame 4 is the arc of the swing,
# so the fire action starts at frame 4: the moment the grenade flies off is exactly when the bat hits it on screen, so the throw timing needs no change.
SINGLES = {
	"1_d": ("3", "walk", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Attack.png", [0, 1, 2, 3]),
		"air": ("Attack.png", [0]),
		"hurt": ("Hurt2.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	"1_f": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}


# Boss A: number 2 of the boss pack, a four-legged missile mech (art_in/default/boss/2/, CraftPix, not in the repo). Each frame 72×72, **not scaled**:
# the hitbox was changed to 56×48 to suit it (it used to be a tall thin 48×64), with the feet 24px below the origin. Output frames 96×80 with anchor (48, 56),
# enough for the part lifted up in the jet jump. Horizontally centred on the body and legs (the BOSS_BODY_ROWS rows) — the missile pod on the back sits further back and would skew it.
# Firing standing is Attack1 (missile pod bursts), firing while walking is Attack2, and in the air it uses the two frames of Attack4 (jets on the legs, jumping up) where the body is raised.
# Attack3 (a beam from the front along the ground) and Sneer (taunt) are not used for now.
BOSS_DIR = os.path.join(HERE, "..", "art_in", "default", "boss", "2")
BOSS_CELL = 72
BOSS_FRAME_W, BOSS_FRAME_H = 96, 80
BOSS_ANCHOR = (48, 56)
BOSS_FOOT = 24
BOSS_BODY_ROWS = (40, 72)
BOSS_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
	"attack_level": ("Attack1.png", [0, 1, 2, 3, 4, 5, 6, 7]),
	"attack_walk": ("Attack2.png", [0, 1, 2, 3, 4, 5]),
	"air": ("Attack4.png", [2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
# HUD portrait: the missile pod and front cut from the first idle frame (32×32, shown 1:1 on the HUD).
BOSS_PORTRAIT = (20, 20, 32, 32)


# The turret (number 6, a tracked turret). The art only has a level barrel; diagonally up / down are drawn by hand-editing the barrel on Idle.png
# (art_in/extra/turret_diag_*.png, containing the pack's pixels, so like the pack it is not in the repo), and transplanted onto the attack and hurt frames when generating.
# Walk is just the tracks rolling; the turret does not walk, so it is unused.
TURRET_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_level": ("Attack.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3]),
}
TURRET_DIAG = {"up": "turret_diag_up.png", "down": "turret_diag_down.png"}
EXTRA = os.path.join(HERE, "..", "art_in", "extra")
TURRET_BODY_RIGHT = 25        # The right edge of the body (the barrel is further right); hand edits may only touch from 2px left of this column rightward
TURRET_BARREL_ROWS = (26, 33)  # The rows of the original level barrel: the diagonal barrel's colours are snapped back to the few that appear here
TURRET_MOUNT_ROWS = (26, 38)   # The barrel mounts on this section: it shifts as a whole when recoiling (the dome moves more, which is squash), and the diagonal barrel follows it
TURRET_MOUNT_SLACK = 16        # The section above may differ by a few pixels (squash during recoil)
TURRET_COLUMN_ROWS = (21, 25)  # The post under the dome, centred horizontally on it
TURRET_OUTLINE_AT = (14, 14)   # The topmost outline pixel of the dome, used for the outline colour


# Enemy E (number 5, the drone). Idle and Walk are drawn identically (propellers spinning while hovering), so only Idle is taken;
# Attack is a discharge straight down, exactly E firing vertically downward.
FLYER_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_down": ("Attack.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3]),
}
FLYER_FRAME = 48
FLYER_ANCHOR = (24, 24)


# ---------------------------------------------------------------- Industrial zone (stage 2)
# Art: CraftPix Industrial Zone Enemies (not in the repo). The format is the same as the cyberpunk set (48×48, feet on the bottom edge),
# so the five on foot go straight through `build_singles` and the flyer through `build_flyer`, without a single new line of code.
# The value is (art directory, whose action's first frame positions it, {output action name: (file, which frames to take)}).
#
# This set **has no diagonal shooting poses** (the cyberpunk patroller has level / diagonally up / diagonally down groups, this set only a level one),
# so 2-C still holds its gun level on screen when firing diagonally. Getting it right would mean hand-editing a few frames into `art_in/extra/` like the turret.
IND_PACK = os.path.join(HERE, "..", "art_in", "default", "industrial-zone-tileset", "industrial-zone-enemies")
IND_OUT = os.path.join(HERE, "..", "skins", "industrial", "enemies")
IND_SINGLES = {
	# 2-A Worker: drops from the sky and charges at the player after landing (reusing D's chase). Running and charging use the same group.
	"2_a": ("1 Worker", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Run.png", [2]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 2-B Heaver: a bare-chested brute, also a charger. Attack is both hands raised overhead and slamming down, used as the charging pose.
	"2_b": ("3 Heaver", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Run.png", [2]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 2-C Specialist: patrolling + shooting. The 8 Attack frames are a whole burst (frames 1~2 muzzle flash, 5~8 ejecting shells);
	# a single shot only takes the first 3 frames, the same length as a cyberpunk patroller group.
	"2_c": ("2 Specialist", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 2-D Hammer: a tracked robot that walks up and swings a hammer. The 8 Attack frames are one full swing — raise, wind up, slam down,
	# **in frame 6 the hammer head hits the ground right in front**, and the damage check has to land on that frame (see HIT_FRAME in enemy_hammer.gd).
	"2_d": ("6 Hammer", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5, 6, 7]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3]),
	}),
	# 2-F Alarmobot: a small tracked robot that sounds the alarm when it spots the player, charges over and self-destructs up close.
	# The Alarm group (red sound waves) is the "alarm going off, about to blow" look; Death itself is the explosion.
	"2_f": ("4 Alarmobot", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3, 4, 5]),
		"walk": ("Run.png", [0, 1, 2, 3]),
		"run": ("Run.png", [0, 1, 2, 3]),
		"attack_level": ("Alarm.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}
# 2-E Copter: a helicopter drone flying overhead and dropping bombs (reusing E's flying + the existing grenade).
# In the 6 Attack frames **the bomb is released in frame 3**, so the grenade leaves on that frame (see enemy_copter.gd).
# Which rows are the body (below the mast and blades): this one's body bottom is as wide as the blades, so the automatic check cannot tell.
IND_FLYER_BODY = (20, 34)
IND_FLYER = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_down": ("Attack.png", [0, 1, 2, 3, 4, 5]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}


def palette_of(folder):
	"""The art's own palette: frames we draw have to be snapped back to these colours (lossy compression brings in lots of near colours)."""
	seen = {}
	for name in os.listdir(folder):
		if not name.lower().endswith(".png"):
			continue
		_, _, pixels = sb.read_png(os.path.join(folder, name))
		for row in pixels:
			for c in row:
				if c[3] > 8:
					seen[c[:3]] = seen.get(c[:3], 0) + 1
	return sorted(seen, key=lambda c: -seen[c])


def snap(pixels, colors):
	return [[(0, 0, 0, 0) if c[3] <= 8 else
		min(colors, key=lambda p: sum((p[i] - c[i]) ** 2 for i in range(3))) + (255,) for c in row] for row in pixels]


def recolor(frame, mapping):
	if not mapping:
		return frame
	return [[mapping[c[:3]] + (c[3],) if c[3] > 8 and c[:3] in mapping else c for c in row] for row in frame]


def frames_of(path, indices):
	_, _, pixels = sb.read_png(path)
	return [sb.cut(pixels, i * CELL, 0, CELL, CELL) for i in indices]


def own_frames(path, colors):
	"""Our own row: each cell is 48 wide and the canvas may be taller than 48; the lowest row is aligned to the frame's bottom edge (the same line as the art's feet)."""
	_, _, pixels = sb.read_png(path)
	pixels = snap(pixels, colors)
	height, width = len(pixels), len(pixels[0])
	bottom = max(y for y, row in enumerate(pixels) if any(c[3] for c in row))
	frames = []
	for i in range(width // CELL):
		frame = sb.blank(CELL, CELL)
		for y in range(height):
			ty = y - bottom + CELL - 1
			if 0 <= ty < CELL:
				frame[ty] = pixels[y][i * CELL:(i + 1) * CELL]
		frames.append(frame)
	return frames


def place(content, anchor_x, where):
	"""Put a 48×48 frame into 80×56: the anchor_x column lines up with the anchor, and the feet (frame bottom) land 16px below the origin."""
	out = sb.blank(FRAME_W, FRAME_H)
	sb.blit(out, content, ANCHOR[0] - int(round(anchor_x)), ANCHOR[1] + 16 - CELL, where)
	return out


def mirror(frame):
	"""Mirror left and right around the anchor column, with the anchor itself staying put (the same approach as the player)."""
	return mirror_about(frame, ANCHOR[0])


def save(folder, name, frames, write, out=None):
	save_frames(folder, name, frames, FRAME_W, FRAME_H, write, out)


def build_walkers(write):
	folder = os.path.join(PACK, "2")
	colors = palette_of(folder)
	clips = {name: frames_of(os.path.join(folder, f), idx) for name, (f, idx) in WALKER_CLIPS.items()}
	clips["prone"] = own_frames(os.path.join(OWN, WALKER_PRONE), colors)
	# The whole character is positioned once: by the torso centre of the first idle frame; the prone group is positioned separately by the shirt centre (see PRONE_TORSO_X)
	anchor_x = sb.torso_center(clips["idle"][0])
	shirt = [x for row in clips["prone"][0] for x, c in enumerate(row) if c[3] > 8 and c[:3] in SHIRT]
	prone_anchor_x = sum(shirt) / len(shirt) - PRONE_TORSO_X
	for variant, mapping in VARIANTS.items():
		for name, frames in clips.items():
			ax = prone_anchor_x if name == "prone" else anchor_x
			right = [place(recolor(f, mapping), ax, "%s %s" % (variant, name)) for f in frames]
			save(variant, "%s_r.png" % name, right, write)
			save(variant, "%s_l.png" % name, [mirror(f) for f in right], write)


## The horizontal centre of the whole frame's content. **Used for those that are not humanoid** (the shark mech lying on the ground, the wheeled cannon cart):
## `sb.torso_center()` measures the "head + upper body" band, and low flat things have not a single pixel in those rows.
def box_center(frame):
	xs = [x for row in frame for x, c in enumerate(row) if c[3] > 8]
	return (min(xs) + max(xs)) / 2.0


def build_singles(write, singles=None, pack=None, out=None):
	"""One piece of art makes one enemy: actions map directly and the whole character is positioned once by one frame.
	The fourth value in the table is "what to position by": `torso` (default, humanoid) or `box` (by the whole frame's bounding box, for the low flat ones)."""
	for name, entry in (singles if singles else SINGLES).items():
		number, anchor_clip, table = entry[0], entry[1], entry[2]
		how = entry[3] if len(entry) > 3 else "torso"
		folder = os.path.join(pack if pack else PACK, number)
		clips = {clip: frames_of(os.path.join(folder, f), idx) for clip, (f, idx) in table.items()}
		anchor_x = sb.torso_center(clips[anchor_clip][0]) if how == "torso" 			else box_center(clips[anchor_clip][0])
		for clip, frames in clips.items():
			right = [place(f, anchor_x, "%s %s" % (name, clip)) for f in frames]
			save(name, "%s_r.png" % clip, right, write, out)
			save(name, "%s_l.png" % clip, [mirror(f) for f in right], write, out)


def build_boss(write):
	clips = {}
	for name, (f, idx) in BOSS_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(BOSS_DIR, f))
		clips[name] = [sb.cut(pixels, i * BOSS_CELL, 0, BOSS_CELL, BOSS_CELL) for i in idx]
	first = clips["idle"][0]
	body = [x for y in range(*BOSS_BODY_ROWS) for x, c in enumerate(first[y]) if c[3] > 8]
	anchor_x = (min(body) + max(body)) / 2.0
	dx = BOSS_ANCHOR[0] - int(round(anchor_x))
	dy = BOSS_ANCHOR[1] + BOSS_FOOT - BOSS_CELL
	for name, frames in clips.items():
		right = []
		for f in frames:
			out = sb.blank(BOSS_FRAME_W, BOSS_FRAME_H)
			sb.blit(out, f, dx, dy, "1_boss %s" % name)
			right.append(out)
		save_frames("1_boss", "%s_r.png" % name, right, BOSS_FRAME_W, BOSS_FRAME_H, write)
		save_frames("1_boss", "%s_l.png" % name, [mirror_about(f, BOSS_ANCHOR[0]) for f in right],
			BOSS_FRAME_W, BOSS_FRAME_H, write)
	x, y, w, h = BOSS_PORTRAIT
	if write:
		sb.write_png(os.path.join(OUT, "1_boss", "portrait.png"), sb.cut(first, x, y, w, h))
	print("  1_boss/portrait.png  %dx%d" % (w, h))


def build_turret(write):
	"""The turret: the level groups use the art directly; diagonally up / down transplant the hand-edited barrel onto every frame (see TURRET_DIAG)."""
	folder = os.path.join(PACK, "6")
	clips = {name: frames_of(os.path.join(folder, f), idx) for name, (f, idx) in TURRET_CLIPS.items()}
	idle = clips["idle"]
	outline = idle[0][TURRET_OUTLINE_AT[1]][TURRET_OUTLINE_AT[0]]
	for aim, source in TURRET_DIAG.items():
		drawn = diag_sheet(os.path.join(EXTRA, source), idle)
		# Attack frames: when the turret recoils the barrel mount shifts back and up, and the diagonal barrel shifts the same
		clips["attack_" + aim] = [graft(f, drawn[0], mount_offset(f, idle[0])) for f in clips["attack_level"]]
		clips["idle_" + aim] = [d["frame"] for d in drawn]
		# Hurt: frame 1 is the same as idle; in frame 2 the whole turret flashes solid yellow, and the new barrel has to be painted the same flash colour
		hurt = clips["hurt"]
		flash_color = most_common(hurt[1], skip=[outline])
		clips["hurt_" + aim] = [graft(hurt[0], drawn[0], (0, 0)), flashed(hurt[1], drawn[1], outline, flash_color)]
	# Horizontally centred on the turret post (the section under the dome); the barrel and tracks do not count
	column = [x for y in range(*TURRET_COLUMN_ROWS) for x, c in enumerate(idle[0][y]) if c[3] > 8]
	anchor_x = (min(column) + max(column)) / 2.0
	for name, frames in clips.items():
		right = [place(f, anchor_x, "turret %s" % name) for f in frames]
		save("1_g", "%s_r.png" % name, right, write)
		save("1_g", "%s_l.png" % name, [mirror(f) for f in right], write)


def diag_sheet(path, idle):
	"""Read a hand-edited diagonal barrel image (only the barrel changed on Idle.png): return each frame's "which pixels changed" and the cleaned whole frame.
	Changes may only be on the barrel side, not a single pixel of the body may move — otherwise it cannot be transplanted onto the attack / hurt frames, so it errors out."""
	width, height, pixels = sb.read_png(path)
	assert width == CELL * len(idle), "%s should be as wide as Idle.png (%d), actually %d" % (path, CELL * len(idle), width)
	assert not any(c[3] > 8 for row in pixels[CELL:] for c in row), "%s still has content below row %d" % (path, CELL)
	barrel_colors = sorted({c[:3] for y in range(*TURRET_BARREL_ROWS) for c in idle[0][y][TURRET_BODY_RIGHT:] if c[3] > 8})
	out = []
	for i, original in enumerate(idle):
		frame = sb.cut(pixels, i * CELL, 0, CELL, CELL)
		changed = [(x, y) for y in range(CELL) for x in range(CELL)
			if visible(frame[y][x]) != visible(original[y][x])
			or (visible(frame[y][x]) and frame[y][x][:3] != original[y][x][:3])]
		stray = [(x, y) for x, y in changed if x < TURRET_BODY_RIGHT - 2]
		assert not stray, "%s frame %d changes the body: %s" % (path, i + 1, stray[:5])
		clean = [row[:] for row in original]
		for x, y in changed:
			c = frame[y][x]
			# The semi-transparent edges and near colours from anti-aliasing when the editor rotated it: binarise the alpha and snap colours back to the barrel's originals
			clean[y][x] = (0, 0, 0, 0) if c[3] < 128 else \
				min(barrel_colors, key=lambda p: sum((p[k] - c[k]) ** 2 for k in range(3))) + (255,)
		out.append({"changed": changed, "frame": clean})
	return out


def visible(c):
	return c[3] >= 128


def mount_offset(frame, idle):
	"""How far this frame's barrel mount (left of the barrel) has moved relative to the first idle frame."""
	best = None
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			miss = 0
			for y in range(*TURRET_MOUNT_ROWS):
				for x in range(TURRET_BODY_RIGHT):
					sx, sy = x + dx, y + dy
					a = frame[sy][sx] if 0 <= sx < CELL and 0 <= sy < CELL else (0, 0, 0, 0)
					b = idle[y][x]
					if (a[3] > 8) != (b[3] > 8) or (a[3] > 8 and a[:3] != b[:3]):
						miss += 1
			if best is None or miss < best[0]:
				best = (miss, dx, dy)
	# The recoil frame has a little squash besides the shift (top edge, barrel root), so a few pixels may differ at the edges; more than that means the art changed and this transplant does not apply
	assert best[0] <= TURRET_MOUNT_SLACK, "The barrel mount does not match the idle frame (off by %d pixels), it is not a plain shift" % best[0]
	return best[1], best[2]


def graft(frame, drawn, offset):
	"""Shift the hand-edited block (the erased level barrel + the newly drawn diagonal barrel) by offset and paste it onto this frame."""
	out = [row[:] for row in frame]
	for x, y in drawn["changed"]:
		tx, ty = x + offset[0], y + offset[1]
		if 0 <= tx < CELL and 0 <= ty < CELL:
			out[ty][tx] = drawn["frame"][y][x]
	return out


def flashed(flash, drawn, outline, flash_color):
	"""Flash frame: within the changed block the outer outline stays black, the rest is painted the flash colour."""
	out = [row[:] for row in flash]
	frame = drawn["frame"]
	for x, y in drawn["changed"]:
		c = frame[y][x]
		if c[3] <= 8:
			out[y][x] = (0, 0, 0, 0)
			continue
		edge = any(not (0 <= x + dx < CELL and 0 <= y + dy < CELL) or frame[y + dy][x + dx][3] <= 8
			for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)])
		out[y][x] = outline if edge and c[:3] == outline[:3] else flash_color
	return out


def most_common(frame, skip):
	count = {}
	for row in frame:
		for c in row:
			if c[3] > 8 and c not in skip:
				count[c] = count.get(c, 0) + 1
	return max(count, key=count.get)


def build_flyer(write, key="1_e", number="5", table=None, pack=None, out_root=None, body_rows=None,
		faces_left=False):
	"""The flyer: the whole set is positioned once by the body (below the propellers) of the first idle frame, with the body centre on the anchor.
	`faces_left`: the art is drawn **facing left** (the basement drone's gun is on the left). It is flipped as a whole frame when read in,
	and everything after treats it as facing right — the output `_r` always faces right, so the visual layer does not need special cases."""
	folder = os.path.join(pack if pack else PACK, number)
	clips = {name: frames_of(os.path.join(folder, f), idx)
		for name, (f, idx) in (table if table else FLYER_CLIPS).items()}
	if faces_left:
		clips = {name: [[list(reversed(row)) for row in f] for f in frames] for name, frames in clips.items()}
	first = clips["idle"][0]
	# Body = the section below the propellers: count down from the widest rows (the propellers), skipping the mast.
	rows = [y for y, row in enumerate(first) if any(c[3] > 8 for c in row)]
	widths = {y: sum(1 for c in first[y] if c[3] > 8) for y in rows}
	if body_rows is None:
		rotor_bottom = max(y for y in rows if widths[y] == max(widths.values()))
		body = [(x, y) for y in rows if y > rotor_bottom and widths[y] > 6
			for x, c in enumerate(first[y]) if c[3] > 8]
	else:
		# **When the body is as wide as the blades the line above cannot tell** (the industrial helicopter's body bottom and blades are both 17 wide,
		# so "the last widest row" lands right on the body bottom with no rows left below). For those the body rows are just written out.
		# The check above is left alone: the green zone drone is already lined up, and changing it for new art would shift that whole image by 1px.
		body = [(x, y) for y in range(body_rows[0], body_rows[1]) if y in widths
			for x, c in enumerate(first[y]) if c[3] > 8]
	xs = [x for x, _ in body]
	top = min(y for y in rows)
	bottom = max(y for y in rows)
	# Horizontally: the body centre; vertically: the centre of the whole aircraft (propellers included) — the 28×20 hitbox counts the propellers in
	dx = FLYER_ANCHOR[0] - int(round((min(xs) + max(xs)) / 2.0))
	dy = FLYER_ANCHOR[1] - int(round((top + bottom) / 2.0))
	for name, frames in clips.items():
		right = []
		for f in frames:
			# Note this must not be called out: it would shadow the output directory parameter
			placed = sb.blank(FLYER_FRAME, FLYER_FRAME)
			sb.blit(placed, f, dx, dy, "flyer %s" % name)
			right.append(placed)
		left = [mirror_about(f, FLYER_ANCHOR[0]) for f in right]
		save_frames(key, "%s_r.png" % name, right, FLYER_FRAME, FLYER_FRAME, write, out_root)
		save_frames(key, "%s_l.png" % name, left, FLYER_FRAME, FLYER_FRAME, write, out_root)


def mirror_about(frame, column):
	out = sb.blank(len(frame[0]), len(frame))
	for y, row in enumerate(frame):
		for x, c in enumerate(row):
			sx = 2 * column - x
			if c[3] > 8:
				if 0 <= sx < len(row):
					out[y][sx] = c
				else:
					sb._clipped.append("out of bounds after mirroring: (%d, %d)" % (x, y))
	return out


def save_frames(folder, name, frames, width, height, write, out=None):
	strip = sb.blank(width * len(frames), height)
	for index, frame in enumerate(frames):
		sb.blit(strip, frame, index * width, 0, "%s/%s" % (folder, name))
	if write:
		sb.write_png(os.path.join(out if out else OUT, folder, name), strip)
	print("  %s/%s  %d frames" % (folder, name, len(frames)))


# ---------------------------------------------------------------- The industrial zone boss (machine operator)
# The art is **two things**: an iron ball floating in the air (Idle / Left / Right / Attack1-2 / Hurt / Death),
# and a mechanical claw hanging on a cable (Move / Up-Down / Attack3-4).
# We treat the ball as the body and the claw as the arm it reaches down with — which fits "the iron ball flies in eight directions, reaches an arm down from above to hit the player below,
# and fires a string of bullets when not using the arm".
#
# Each ball frame is 96×96 with the body about 90×90 **drawn in the middle of the cell**, so the whole set is carried over as is with the anchor at the cell centre.
# Hitbox 72×72: a size smaller than the picture, the same rule as Boss A's "keep the art's size, make the hitbox slightly smaller".
BOSS2_DIR = os.path.join(IND_PACK, "..", "industrial-zone-boss", "3 Machine operator")
BOSS2_OUT = "2_boss"
BOSS2_CELL = 96
BOSS2_ANCHOR = (48, 48)
BOSS2_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Right.png", [0, 1, 2, 3, 4, 5, 6, 7]),
	"attack_level": ("Attack2.png", [0, 1, 2, 3, 4, 5, 6, 7]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
# HUD portrait: the 32×32 in the middle of the ball, with the red ring and the crown inside.
BOSS2_PORTRAIT = (32, 32, 32, 32)
# The arm is **not used by frame**: the 6 frames in the art only have 6 cable lengths, while how far it reaches is up to gameplay.
# So it is split into two images, "one row of cable" and "the claw"; the cable is tiled vertically to the needed length and the claw is stuck on the end.
# The claw comes from the frame with the longest cable (Up-Down frame 2), the closed claw from the last frame of Attack4.
BOSS2_ARM = {"open": ("Up-Down.png", 2), "shut": ("Attack4.png", 5)}
# The horizontal span the claw takes (the same in all six frames), and which row of cable to take (the middle; any row tiles seamlessly).
BOSS2_CLAW_X = (28, 68)
BOSS2_CABLE_ROW = 32


def build_boss_operator(write):
	# **frames_of cannot be used**: it cuts by `CELL` (48), while the boss frames are 96
	def frames_at(file_name, indices):
		_, _, pixels = sb.read_png(os.path.join(BOSS2_DIR, file_name))
		return [sb.cut(pixels, i * BOSS2_CELL, 0, BOSS2_CELL, BOSS2_CELL) for i in indices]

	clips = {c: frames_at(f, idx) for c, (f, idx) in BOSS2_CLIPS.items()}
	for name, frames in clips.items():
		right = [sb.blank(BOSS2_CELL, BOSS2_CELL) for _ in frames]
		for out_frame, f in zip(right, frames):
			sb.blit(out_frame, f, 0, 0, "2_boss %s" % name)
		left = [mirror_about(f, BOSS2_ANCHOR[0]) for f in right]
		save_frames(BOSS2_OUT, "%s_r.png" % name, right, BOSS2_CELL, BOSS2_CELL, write, IND_OUT)
		save_frames(BOSS2_OUT, "%s_l.png" % name, left, BOSS2_CELL, BOSS2_CELL, write, IND_OUT)
	portrait = sb.cut(clips["idle"][0], *BOSS2_PORTRAIT)
	if write:
		sb.write_png(os.path.join(IND_OUT, BOSS2_OUT, "portrait.png"), portrait)
	print("  %s/portrait.png  %dx%d" % (BOSS2_OUT, len(portrait[0]), len(portrait)))

	# The arm: one row of cable + the open claw + the closed claw. All three are aligned on the cable's centre column,
	# so in the game "draw the cable down from the bottom of the ball and stick the claw on the end" needs no further offset.
	left_x, right_x = BOSS2_CLAW_X
	for key, (file_name, index) in BOSS2_ARM.items():
		frame = frames_at(file_name, [index])[0]
		rows = [y for y in range(BOSS2_CELL)
			if sum(1 for x in range(BOSS2_CELL) if frame[y][x][3] > 8) > 6 and y > 20]
		claw = sb.blank(right_x - left_x, max(rows) - min(rows) + 1)
		sb.blit(claw, sb.cut(frame, left_x, min(rows), right_x - left_x, len(claw)), 0, 0, "claw")
		if write:
			sb.write_png(os.path.join(IND_OUT, BOSS2_OUT, "arm_claw_%s.png" % key), claw)
		print("  %s/arm_claw_%s.png  %dx%d" % (BOSS2_OUT, key, len(claw[0]), len(claw)))
	cable_frame = frames_at(BOSS2_ARM["open"][0], [BOSS2_ARM["open"][1]])[0]
	# The cable only takes its own columns (4px wide), not the whole strip with the claw:
	# in the game the cable is drawn down **by its centre**, and blank space left on either side would make it look off to one side.
	row = cable_frame[BOSS2_CABLE_ROW]
	columns = [x for x in range(BOSS2_CELL) if row[x][3] > 8]
	cable = sb.blank(max(columns) - min(columns) + 1, 1)
	sb.blit(cable, sb.cut(cable_frame, min(columns), BOSS2_CABLE_ROW, len(cable[0]), 1), 0, 0, "cable")
	if write:
		sb.write_png(os.path.join(IND_OUT, BOSS2_OUT, "arm_cable.png"), cable)
	print("  %s/arm_cable.png  %dx1 (tiled vertically, drawn by centre)" % (BOSS2_OUT, len(cable[0])))


# ---------------------------------------------------------------- Bar street (stage 3)
# Art: CraftPix Bar Street Enemies (not in the repo). The format is still 48×48 with the feet on the bottom edge,
# so all six go through `build_singles` — this stage has no flyers (number 5, the shark mech, is **fixed to the ground** and fires along it).
#
# **Gunner number 2 comes with three aim angles** (Attack1 level / Attack2 diagonally up / Attack3 diagonally down),
# exactly matching the engine's existing `attack_level` / `attack_up` / `attack_down` —
# which is just what stage 2's 2-C lacks, so it holds its gun level on screen when firing diagonally (see "Industrial zone art pack").
BAR_PACK = os.path.join(HERE, "..", "art_in", "default", "bar-street-tileset", "enemies")
BAR_OUT = os.path.join(HERE, "..", "skins", "bar_street", "enemies")
BAR_SINGLES = {
	# 3-A Knifeman: winds up, then dashes a stretch to stab. The dash uses the walk group played fast (`run` 12fps).
	"3_a": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 3-B Gunner: patrolling + shooting + **real diagonal shots** (all three angles come with the art).
	"3_b": ("2", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack1.png", [0, 1, 2, 3]),
		"attack_up": ("Attack2.png", [0, 1, 2, 3]),
		"attack_down": ("Attack3.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 3-C Swordsman: leaps at the player and sweeps on landing. **In the air it uses the first frame of the sword swing** (the raised sword pose);
	# the art has no jump frames, and using the walk group in the air would look like gliding on flat ground.
	"3_c": ("3", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Attack.png", [0]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3]),
	}),
	# 3-D Brute: the one that tanks damage from the front, walking slowly and never charging.
	"3_d": ("4", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 3-E Shark mech: **fixed to the ground**, firing along the ground. It does not walk, so `walk` is not taken.
	# It is only 11px tall, lying on the ground — positioned by "torso" there would not be a single pixel in that band, so it is centred on its bounding box.
	"3_e": ("5", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"attack_level": ("Attack.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}, "box"),
	# 3-F Cannon cart: a wheeled turret that moves very slowly and stops to fire a string.
	"3_f": ("6", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3]),
	}),
}


# ---------------------------------------------------------------- The bar street boss (unicycle mech)
# Art `bosses/3`. Each frame 96×96 with the body about 53×64 riding a single wheel, **feet on the bottom edge**.
# Hitbox 48×56 (a size smaller than the picture, like the first two bosses); output frames 112×96 leave room for the barrel sticking out.
#
# This pack's names do not match its contents; **they were identified by looking at the pictures**:
# `Attack1` is the cannon shot, `Attack3` throws a bomb up (arm raised + a red trajectory),
# `Special` is actually the forward-leaning roll (the ram), and `Attack4` is really **the bomb's own explosion animation** (not a boss move).
# The bomb uses the existing enemy grenade (`enemy_grenade.tscn`): `Grenade.launch()` already flies in an arc and bounces once on landing before exploding,
# which is exactly "thrown into the air and crashing down". The 96×96 `Bomb.png` is too big for an 8px hitbox, so it is unused.
BOSS3_DIR = os.path.join(BAR_PACK, "..", "bosses", "3")
BOSS3_CELL = 96
# **Frames have to be taller than the art**: the red trajectory in the arm-raised throw group reaches above the art's frame,
# and output 96 tall it would be cut off — that is the warning that "a bomb is coming", which cannot be lost.
BOSS3_FRAME_W, BOSS3_FRAME_H = 112, 120
BOSS3_ANCHOR_Y = 68
BOSS3_OUT = "3_boss"
## How far below the origin the feet land (= half the hitbox height).
BOSS3_FOOT = 28
BOSS3_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3, 4, 5]),
	"walk": ("Walk.png", [0, 1, 2, 3]),
	"run": ("Special.png", [0, 1, 2, 3, 4, 5]),        # Forward-leaning roll = ram
	"attack_level": ("Attack1.png", [0, 1, 2, 3, 4, 5]),
	"attack_up": ("Attack3.png", [0, 1, 2, 3, 4, 5]),  # Arm raised, throwing a bomb up
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## HUD portrait: the 32×32 of the upper body (the cockpit and that antenna).
BOSS3_PORTRAIT = (20, 34, 32, 32)


def build_boss_wheel(write):
	def frames_at(file_name, indices):
		_, _, pixels = sb.read_png(os.path.join(BOSS3_DIR, file_name))
		return [sb.cut(pixels, i * BOSS3_CELL, 0, BOSS3_CELL, BOSS3_CELL) for i in indices]

	clips = {c: frames_at(f, idx) for c, (f, idx) in BOSS3_CLIPS.items()}
	# The whole set is positioned once by the first idle frame (like the first two bosses): horizontally centred on the body's bounding box,
	# vertically with the feet BOSS3_FOOT below the origin.
	first = clips["idle"][0]
	xs = [x for row in first for x, c in enumerate(row) if c[3] > 8]
	dx = BOSS3_FRAME_W // 2 - int(round((min(xs) + max(xs)) / 2.0))
	dy = BOSS3_ANCHOR_Y + BOSS3_FOOT - BOSS3_CELL
	for name, frames in clips.items():
		right = []
		for f in frames:
			out = sb.blank(BOSS3_FRAME_W, BOSS3_FRAME_H)
			sb.blit(out, f, dx, dy, "3_boss %s" % name)
			right.append(out)
		left = [mirror_about(f, BOSS3_FRAME_W // 2) for f in right]
		save_frames(BOSS3_OUT, "%s_r.png" % name, right, BOSS3_FRAME_W, BOSS3_FRAME_H, write, BAR_OUT)
		save_frames(BOSS3_OUT, "%s_l.png" % name, left, BOSS3_FRAME_W, BOSS3_FRAME_H, write, BAR_OUT)
	x, y, w, h = BOSS3_PORTRAIT
	portrait = sb.cut(clips["idle"][0], x, y, w, h)
	if write:
		sb.write_png(os.path.join(BAR_OUT, BOSS3_OUT, "portrait.png"), portrait)
	print("  %s/portrait.png  %dx%d" % (BOSS3_OUT, w, h))


# ---------------------------------------------------------------- Basement (stage 4, climbed vertically)
# Art: CraftPix Basement Enemies (`basement-tileset/enemies/`, not in the repo), still 48×48 with the feet on the bottom edge.
# How they fight was decided with the user in 2026-10 (this stage is climbed upward, so threats come from above, below and the sides):
BASE_PACK = os.path.join(HERE, "..", "art_in", "default", "basement-tileset", "enemies")
BASE_OUT = os.path.join(HERE, "..", "skins", "basement", "enemies")
BASE_SINGLES = {
	# 4-A Bare-chested thug: **a pursuer coming up from below** (D's approach, able to jump up the platforms layer by layer).
	# The Walk group is drawn as a sprint (body leaning forward, arms swinging), so walking and charging use the same group; in the air it takes one frame from it.
	"4_a": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Walk.png", [2]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 4-B Cat-ear girl: **platform guard**. The 6 Attack frames = a flick, raised overhead (frames 3 and 4, the wind-up),
	# **in frame 5 the blade flash sweeps to its farthest** — the damage lands on this frame.
	"4_b": ("2", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 4-C Man in a suit: a three-way gunner. The art comes with level / diagonally up / diagonally down groups, real diagonal shots like stage 3's 3-B.
	"4_c": ("3", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack1.png", [0, 1, 2, 3]),
		"attack_up": ("Attack2.png", [0, 1, 2, 3]),
		"attack_down": ("Attack3.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 4-E Spider turret: a floor-guarding turret that creeps along and fires a level string. Not humanoid, centred on its bounding box.
	"4_e": ("5", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}, "box"),
	# 4-F Skull-shirt thug: **knocks you off the platform with one punch**. In the 6 Attack frames the whole arm swings out farthest in frame 5 — the knockback lands on this frame.
	"4_f": ("6", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}
# 4-D Drone: **flies at the player's height** and fires level once lined up. The art is drawn **facing left** (gun on the left),
# so it is flipped first when generating. The body is rows 19~30 (antenna above, nozzle below).
# Its Attack is only the nozzle underneath flashing, with no muzzle flash drawn — the flash when firing is drawn separately by the effects layer (`Fx`).
BASE_FLYER_BODY = (19, 30)
BASE_FLYER = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_level": ("Attack.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}


# ---------------------------------------------------------------- The basement boss (skull)
# Art `bosses/2`. Each frame 96×96: a big floating skull + a bony hand, the body at x 10..53, y 23..77 in the frame,
# **centred around (32, 50)**. The actions were identified by looking at the pictures:
# Attack1 / Attack2 are almost identical: the first two frames charge up, and frames 3 and 4 fire a **level laser** from the bony hand (red and black stripes);
# Attack3: red balls appear around it, and in frame 5 a **small skull** drops from its hand — the summon;
# Idle2 / Walk2 / Hurt2 / Death2 are the 48×48 **small skull** itself (the summoned minion);
# Sneer: the bony hand tucked away leaving only the skull — the taunt, used at the shift when health drops past half.
#
# **Output frames 128×96, anchor (64, 48)**: in the art the laser reaches the right edge of the frame (x 95), and after shifting right 32 to line up with the anchor
# it reaches 127; left / right mirroring flips around the anchor, so the left side needs the same width.
# The laser itself is drawn separately by the visual at the length gameplay gives (`BossSkullAppearance`); the piece in the art is only the start.
BOSS4_DIR = os.path.join(BASE_PACK, "..", "bosses", "2")
BOSS4_OUT = "4_boss"
BOSS4_CELL = 96
BOSS4_FRAME_W = 128
BOSS4_FRAME_H = 96
BOSS4_ANCHOR = (64, 48)
## The centre of the body in the art (the point lined up with the anchor).
BOSS4_BODY = (32, 50)
BOSS4_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3]),
	"charge": ("Attack1.png", [0, 1]),
	"beam": ("Attack1.png", [2, 3]),
	"summon": ("Attack3.png", [0, 1, 2, 3, 4, 5]),
	"sneer": ("Sneer.png", [0, 1, 2, 3, 4, 5]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## The laser strip: one column (x 90) taken from Attack1's beam frames. The thick one is frame 3 (6 rows), the one as it fades is frame 4 (4 rows).
BOSS4_BEAM = {"beam_thick": (2, 63, 69), "beam_thin": (3, 64, 68)}
BOSS4_BEAM_COLUMN = 90
## HUD portrait: the skull.
BOSS4_PORTRAIT = (16, 22, 32, 32)
## The small skull (48×48, centred around (23, 23)), going down the flyer path: the body is rows 17~30.
MINION4_OUT = "4_minion"
MINION4_BODY = (17, 30)
MINION4 = {
	"idle": ("Idle2.png", [0, 1, 2, 3]),
	"walk": ("Walk2.png", [0, 1, 2, 3]),
	"hurt": ("Hurt2.png", [0, 1]),
	"death": ("Death2.png", [0, 1, 2, 3]),
}


def build_boss_skull(write):
	dx = BOSS4_ANCHOR[0] - BOSS4_BODY[0]
	dy = BOSS4_ANCHOR[1] - BOSS4_BODY[1]
	for name, (f, idx) in BOSS4_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(BOSS4_DIR, f))
		right = []
		for i in idx:
			frame = sb.cut(pixels, i * BOSS4_CELL, 0, BOSS4_CELL, BOSS4_CELL)
			placed = sb.blank(BOSS4_FRAME_W, BOSS4_FRAME_H)
			sb.blit(placed, frame, dx, dy, "boss4 %s" % name)
			right.append(placed)
		left = [mirror_about(fr, BOSS4_ANCHOR[0]) for fr in right]
		save_frames(BOSS4_OUT, "%s_r.png" % name, right, BOSS4_FRAME_W, BOSS4_FRAME_H, write, BASE_OUT)
		save_frames(BOSS4_OUT, "%s_l.png" % name, left, BOSS4_FRAME_W, BOSS4_FRAME_H, write, BASE_OUT)
	_, _, attack = sb.read_png(os.path.join(BOSS4_DIR, "Attack1.png"))
	for name, (frame, top, bottom) in BOSS4_BEAM.items():
		column = [[attack[y][frame * BOSS4_CELL + BOSS4_BEAM_COLUMN]] for y in range(top, bottom)]
		if write:
			sb.write_png(os.path.join(BASE_OUT, BOSS4_OUT, name + ".png"), column)
		print("  %s/%s.png  1x%d" % (BOSS4_OUT, name, bottom - top))
	_, _, idle = sb.read_png(os.path.join(BOSS4_DIR, "Idle.png"))
	x, y, w, h = BOSS4_PORTRAIT
	if write:
		sb.write_png(os.path.join(BASE_OUT, BOSS4_OUT, "portrait.png"), sb.cut(idle, x, y, w, h))
	build_flyer(write, MINION4_OUT, ".", MINION4, BOSS4_DIR, BASE_OUT, MINION4_BODY)


# ---------------------------------------------------------------- Lab (stage 5)
# Art: CraftPix Lab Enemies (`lab-tileset/enemies/`, not in the repo). Numbers 1~3 are small 48×48 figures with the feet on the bottom edge, going through `build_singles`;
# numbers 4~6 are 96×96 turret heads and `Mech base/` holds the bases, stacked together into large mechs (`build_lab_mechs()`).
LAB_PACK = os.path.join(HERE, "..", "art_in", "default", "lab-tileset", "enemies")
LAB_OUT = os.path.join(HERE, "..", "skins", "lab", "enemies")
LAB_SINGLES = {
	# 5-A Scientist (black hair): patrols and throws acid flasks forward (in Attack frame 4 the arm swings furthest forward — the release lands on this frame);
	# **transforms** when hit or closed in on (Transform 4 frames, the last already looks like the mutant), and becomes a 5-C afterwards.
	"5_a": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"transform": ("Transform.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 5-B Scientist (grey hair): transforms as soon as it sees the player.
	"5_b": ("2", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"transform": ("Transform.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 5-C Mutant: walks up, raises its arm, smashes the ground. In the 6 Attack frames the big arm hits the ground in frame 4 (index 3) — damage and shockwave land on this frame.
	"5_c": ("3", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}


## Large mech = a turret head (numbers 4~6) stacked on a base (`Mech base/`): the head's bottom is at row 62 and the bases start at rows 61~63,
## **stacked straight in the same 96×96 frame they join up**, no shifting needed. Output frames stay 96×96, with the anchor at the body centre (set in the visual scene).
## Table: key → (anchor, flipped upside down or not, {action: (head file, frames, base file, base frames (None = frame 0 every frame))}).
## - 5-D Stationary turret: machine-gun head + tracks. The body column's centre is at x 46 and the feet at row 72 → anchor (46, 56); muzzle at (73, 48).
## - 5-F Ceiling emitter: emitter head + a small transporter as the mount, **flipped upside down as a whole** (hanging from the ceiling).
## Flipped, the mount is on top and the head below; the head's centre (45, 45) is the anchor, and the top of the mount (the ceiling) is 20 above it.
LAB_MECHS = {
	"5_d": ((46, 56), False, {
		"idle": ("5/Idle.png", [0, 1, 2, 3, 4, 5], "Mech base/Walk2.png", None),
		"attack_level": ("5/Attack.png", [0, 1, 2, 3, 4, 5], "Mech base/Walk2.png", None),
		"hurt": ("5/Hurt.png", [0, 1], "Mech base/Hurt2.png", [0, 1]),
	}),
	"5_f": ((45, 45), True, {
		"idle": ("4/Idle.png", [0, 1, 2, 3], "Mech base/Hurt3.png", None),
		"attack_level": ("4/Attack.png", [0, 1, 2, 3], "Mech base/Hurt3.png", None),
		"hurt": ("4/Hurt.png", [0, 1], "Mech base/Hurt3.png", [0, 1]),
	}),
}
## 5-E The spider claw arm that digs out of the ground: claw-arm head + spider legs. The body column's centre is x 46, feet at row 76 → anchor (46, 60).
## Walking is the legs' 6 frames with the head's 4 idle frames (cycling); in the 6 attack frames the claw arm sweeps from the right all the way to the left (the arm swings to the other side in frames 5 and 6),
## and in gameplay it plays while turning around, which is exactly "spin in place and sweep both sides".
## `emerge` (digging out) is assembled here: in the first 4 frames the **track** on the ground slides aside, in the last 4 the mech rises from under the floor
## (pixels below the floor line cut off). While buried it stays on frame 1 — only a track on the ground, which is the player's warning.
LAB_BURROWER = {
	"anchor": (46, 60),
	"floor": 76,
	"idle": ("6/Idle.png", [0, 1, 2, 3], "Mech base/Walk1.png", [0]),
	"walk": ("6/Idle.png", [0, 1, 2, 3, 0, 1], "Mech base/Walk1.png", [0, 1, 2, 3, 4, 5]),
	"attack_level": ("6/Attack.png", [0, 1, 2, 3, 4, 5], "Mech base/Walk1.png", [0]),
	"hurt": ("6/Hurt.png", [0, 1], "Mech base/Hurt1.png", [0, 1]),
	# How far the track (`Walk2` frame 1, rows 63~71) slides right, and how deep the mech is still buried each frame
	"hatch": ("Mech base/Walk2.png", 0),
	"hatch_slide": [0, 8, 16, 26, 28, 28, 28, 28],
	"rise": [None, None, None, None, 40, 28, 16, 6],
}
MECH_CELL = 96
## The drop of poison 5-F drips: only the bottom 30 rows of the drop in `Acid1` frame 1 (with a long tail, 25×59) — a ball with a short tail.
POISON_DRIP = ("Acid1.png", (24, 30, 25, 30))


def build_lab_mechs(write):
	def frames_of_cell(rel, indices):
		_, _, pixels = sb.read_png(os.path.join(LAB_PACK, *rel.split("/")))
		return [sb.cut(pixels, i * MECH_CELL, 0, MECH_CELL, MECH_CELL) for i in indices]

	for key, (anchor, flip, clips) in LAB_MECHS.items():
		for clip, (head_rel, head_idx, base_rel, base_idx) in clips.items():
			heads = frames_of_cell(head_rel, head_idx)
			bases = frames_of_cell(base_rel, base_idx if base_idx is not None else [0])
			right = []
			for i, head in enumerate(heads):
				frame = sb.blank(MECH_CELL, MECH_CELL)
				sb.blit(frame, bases[i % len(bases)], 0, 0, "%s %s base" % (key, clip))
				sb.blit(frame, head, 0, 0, "%s %s head" % (key, clip))
				if flip:
					frame = frame[::-1]
				right.append(frame)
			left = [mirror_about(f, anchor[0]) for f in right]
			save_frames(key, "%s_r.png" % clip, right, MECH_CELL, MECH_CELL, write, LAB_OUT)
			save_frames(key, "%s_l.png" % clip, left, MECH_CELL, MECH_CELL, write, LAB_OUT)
	build_lab_burrower(write, frames_of_cell)
	rel, (x, y, w, h) = POISON_DRIP
	_, _, pixels = sb.read_png(os.path.join(LAB_PACK, "..", "4 Animated objects", rel))
	drip = sb.cut(pixels, x, y, w, h)
	out = os.path.join(HERE, "..", "skins", "lab", "projectiles", "poison_drip", "spin.png")
	if write:
		sb.write_png(out, drip)
	print("  projectiles/poison_drip/spin.png  %dx%d" % (w, h))


def build_lab_burrower(write, frames_of_cell):
	spec = LAB_BURROWER
	anchor, floor = spec["anchor"], spec["floor"]

	def stack(head, base):
		frame = sb.blank(MECH_CELL, MECH_CELL)
		sb.blit(frame, base, 0, 0, "5_e base")
		sb.blit(frame, head, 0, 0, "5_e head")
		return frame

	clips = {}
	for clip in ("idle", "walk", "attack_level", "hurt"):
		head_rel, head_idx, base_rel, base_idx = spec[clip]
		heads = frames_of_cell(head_rel, head_idx)
		bases = frames_of_cell(base_rel, base_idx)
		clips[clip] = [stack(h, bases[i % len(bases)]) for i, h in enumerate(heads)]
	clips["run"] = clips["walk"]
	# Digging out: the track slides aside and the mech rises from under the floor
	hatch_rel, hatch_frame = spec["hatch"]
	hatch = frames_of_cell(hatch_rel, [hatch_frame])[0]
	# The track's bottom is at row 71; move it down to lie exactly on the floor line
	hatch_drop = floor - 72
	mech = clips["idle"][0]
	emerge = []
	for slide, sunk in zip(spec["hatch_slide"], spec["rise"]):
		frame = sb.blank(MECH_CELL, MECH_CELL)
		if sunk is not None:
			for yy in range(MECH_CELL):
				ty = yy + sunk
				if ty >= floor or ty >= MECH_CELL:
					continue
				for xx in range(MECH_CELL):
					if mech[yy][xx][3] > 8:
						frame[ty][xx] = mech[yy][xx]
		for yy in range(MECH_CELL):
			ty = yy + hatch_drop
			if not 0 <= ty < MECH_CELL:
				continue
			for xx in range(MECH_CELL):
				tx = xx + slide
				if hatch[yy][xx][3] > 8 and 0 <= tx < MECH_CELL:
					frame[ty][tx] = hatch[yy][xx]
		emerge.append(frame)
	clips["emerge"] = emerge
	for clip, right in clips.items():
		left = [mirror_about(f, anchor[0]) for f in right]
		save_frames("5_e", "%s_r.png" % clip, right, MECH_CELL, MECH_CELL, write, LAB_OUT)
		save_frames("5_e", "%s_l.png" % clip, left, MECH_CELL, MECH_CELL, write, LAB_OUT)


# ---------------------------------------------------------------- The lab's mid-level boss (mutant gunner, `boss/1`)
# Each frame 72×72, the body at x 9..44 with the feet on the bottom edge; the body column (legs) centre is x 25. The actions were identified by looking at the pictures:
# Attack1 fires the laser standing (frame 4 a thick white beam, frame 5 a thin green one, reaching the frame edge), Attack2 fires while walking, Attack3 a front kick,
# Attack4 a forward thrust (the rifle-butt ram), Special the gun lifted slightly (charging, used as the warning).
# **Output frames 128×72, anchor (64, 48)**: the laser reaches the art's frame edge (x 71), and after shifting right 39 to line up with the anchor it reaches 110;
# mirroring flips around the anchor, so both sides need that width. Hitbox 32×48 (feet 24 below the origin).
# The laser itself is drawn separately by the visual at the length gameplay gives (the same approach as the basement skull): one column from the two beam frames.
LAB_MIDBOSS_DIR = os.path.join(LAB_PACK, "..", "boss", "1")
LAB_MIDBOSS_OUT = "5_midboss"
LAB_MIDBOSS_CELL = 72
LAB_MIDBOSS_FRAME = (128, 72)
LAB_MIDBOSS_ANCHOR = (64, 48)
LAB_MIDBOSS_BODY_X = 25
LAB_MIDBOSS_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
	"charge": ("Special.png", [0, 1, 2, 3]),
	"beam": ("Attack1.png", [3, 4]),
	"attack_level": ("Attack1.png", [0, 1, 2, 3, 4, 5]),
	"attack_walk": ("Attack2.png", [0, 1, 2, 3, 4, 5]),
	"kick": ("Attack3.png", [0, 1, 2, 3, 4, 5]),
	"lunge": ("Attack4.png", [0, 1, 2, 3, 4, 5]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## The laser strip: the x 60 column in Attack1's beam frames. The thick one is frame 4 (rows 41~45), the thin one frame 5.
LAB_MIDBOSS_BEAM = {"beam_thick": (3, 41, 46), "beam_thin": (4, 42, 45)}
LAB_MIDBOSS_BEAM_COLUMN = 60
## HUD portrait: the head and gun.
LAB_MIDBOSS_PORTRAIT = (12, 20, 32, 32)


def build_lab_midboss(write):
	dx = LAB_MIDBOSS_ANCHOR[0] - LAB_MIDBOSS_BODY_X
	fw, fh = LAB_MIDBOSS_FRAME
	for name, (f, idx) in LAB_MIDBOSS_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(LAB_MIDBOSS_DIR, f))
		right = []
		for i in idx:
			frame = sb.cut(pixels, i * LAB_MIDBOSS_CELL, 0, LAB_MIDBOSS_CELL, LAB_MIDBOSS_CELL)
			placed = sb.blank(fw, fh)
			sb.blit(placed, frame, dx, 0, "midboss %s" % name)
			right.append(placed)
		left = [mirror_about(fr, LAB_MIDBOSS_ANCHOR[0]) for fr in right]
		save_frames(LAB_MIDBOSS_OUT, "%s_r.png" % name, right, fw, fh, write, LAB_OUT)
		save_frames(LAB_MIDBOSS_OUT, "%s_l.png" % name, left, fw, fh, write, LAB_OUT)
	_, _, attack = sb.read_png(os.path.join(LAB_MIDBOSS_DIR, "Attack1.png"))
	for name, (frame, top, bottom) in LAB_MIDBOSS_BEAM.items():
		column = [[attack[y][frame * LAB_MIDBOSS_CELL + LAB_MIDBOSS_BEAM_COLUMN]] for y in range(top, bottom)]
		if write:
			sb.write_png(os.path.join(LAB_OUT, LAB_MIDBOSS_OUT, name + ".png"), column)
		print("  %s/%s.png  1x%d" % (LAB_MIDBOSS_OUT, name, bottom - top))
	_, _, idle = sb.read_png(os.path.join(LAB_MIDBOSS_DIR, "Idle.png"))
	x, y, w, h = LAB_MIDBOSS_PORTRAIT
	if write:
		sb.write_png(os.path.join(LAB_OUT, LAB_MIDBOSS_OUT, "portrait.png"), sb.cut(idle, x, y, w, h))
	print("  %s/portrait.png  %dx%d" % (LAB_MIDBOSS_OUT, w, h))


## The stage boss "biopod" (art `boss/3`): it flies, facing right (thrusters on the left). Frames 72×72 with the body centre at (26, 34).
## Output frames 144×96 with the anchor (72, 48) on the body centre — the laser and muzzle flashes reach the art's right edge, so mirroring needs room on both sides.
## Files vs contents: Attack1/2 are the same horizontal eye laser, Attack3 curls up into a round shell, Attack4_1/2/3 are the three cannons straight down / diagonally down / level,
## Special is the blades spinning once (played when changing position), Death falls and breaks in two.
LAB_POD_DIR = os.path.join(LAB_PACK, "..", "boss", "3")
LAB_POD_OUT = "5_boss"
LAB_POD_CELL = 72
LAB_POD_FRAME = (144, 96)
LAB_POD_ANCHOR = (72, 48)
LAB_POD_CENTER = (26, 34)
LAB_POD_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3]),
	"charge": ("Attack1.png", [0, 1]),
	"beam": ("Attack1.png", [3, 4]),
	"shell": ("Attack3.png", [2, 3, 4, 5]),
	"cannon_down": ("Attack4_1.png", [0, 1, 2, 3]),
	"cannon_diag": ("Attack4_2.png", [0, 1, 2, 3]),
	"cannon_level": ("Attack4_3.png", [0, 1, 2, 3]),
	"spin": ("Special.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## The laser strip: the x 70 column in Attack1's beam frames. The thick one is frame 4 (rows 30~41), the thin one frame 6 (rows 32~37).
LAB_POD_BEAM = {"beam_thick": (3, 30, 42), "beam_thin": (5, 32, 38)}
LAB_POD_BEAM_COLUMN = 70
## HUD portrait: the eye.
LAB_POD_PORTRAIT = (12, 18, 32, 32)


def build_lab_pod(write):
	dx = LAB_POD_ANCHOR[0] - LAB_POD_CENTER[0]
	dy = LAB_POD_ANCHOR[1] - LAB_POD_CENTER[1]
	fw, fh = LAB_POD_FRAME
	for name, (f, idx) in LAB_POD_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(LAB_POD_DIR, f))
		right = []
		for i in idx:
			frame = sb.cut(pixels, i * LAB_POD_CELL, 0, LAB_POD_CELL, LAB_POD_CELL)
			placed = sb.blank(fw, fh)
			sb.blit(placed, frame, dx, dy, "pod %s" % name)
			right.append(placed)
		left = [mirror_about(fr, LAB_POD_ANCHOR[0]) for fr in right]
		save_frames(LAB_POD_OUT, "%s_r.png" % name, right, fw, fh, write, LAB_OUT)
		save_frames(LAB_POD_OUT, "%s_l.png" % name, left, fw, fh, write, LAB_OUT)
	_, _, attack = sb.read_png(os.path.join(LAB_POD_DIR, "Attack1.png"))
	for name, (frame, top, bottom) in LAB_POD_BEAM.items():
		column = [[attack[y][frame * LAB_POD_CELL + LAB_POD_BEAM_COLUMN]] for y in range(top, bottom)]
		if write:
			sb.write_png(os.path.join(LAB_OUT, LAB_POD_OUT, name + ".png"), column)
		print("  %s/%s.png  1x%d" % (LAB_POD_OUT, name, bottom - top))
	_, _, idle = sb.read_png(os.path.join(LAB_POD_DIR, "Idle.png"))
	x, y, w, h = LAB_POD_PORTRAIT
	if write:
		sb.write_png(os.path.join(LAB_OUT, LAB_POD_OUT, "portrait.png"), sb.cut(idle, x, y, w, h))
	print("  %s/portrait.png  %dx%d" % (LAB_POD_OUT, w, h))


def build_lab(write):
	if not os.path.isdir(LAB_PACK):
		sys.exit("Cannot find the lab enemy art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(LAB_PACK))
	build_singles(write, LAB_SINGLES, LAB_PACK, LAB_OUT)
	build_lab_mechs(write)
	build_lab_midboss(write)
	build_lab_pod(write)


def build_basement(write):
	if not os.path.isdir(BASE_PACK):
		sys.exit("Cannot find the basement enemy art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(BASE_PACK))
	build_singles(write, BASE_SINGLES, BASE_PACK, BASE_OUT)
	build_flyer(write, "4_d", "4", BASE_FLYER, BASE_PACK, BASE_OUT, BASE_FLYER_BODY, faces_left=True)
	build_boss_skull(write)


def build_industrial(write):
	if not os.path.isdir(IND_PACK):
		sys.exit("Cannot find the industrial zone enemy art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(IND_PACK))
	build_singles(write, IND_SINGLES, IND_PACK, IND_OUT)
	build_flyer(write, "2_e", "5 Copter", IND_FLYER, IND_PACK, IND_OUT, IND_FLYER_BODY)
	build_boss_operator(write)


def build_bar_street(write):
	if not os.path.isdir(BAR_PACK):
		sys.exit("Cannot find the bar street enemy art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(BAR_PACK))
	build_singles(write, BAR_SINGLES, BAR_PACK, BAR_OUT)
	build_boss_wheel(write)


def main():
	write = "--check" not in sys.argv
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	if only == ["lab"]:
		print("Lab (stage 5) enemies:")
		build_lab(write)
		_report(write)
		return
	if only == ["basement"]:
		print("The six basement (stage 4) enemies:")
		build_basement(write)
		_report(write)
		return
	if only == ["bar_street"]:
		print("The six bar street (stage 3) enemies:")
		build_bar_street(write)
		_report(write)
		return
	if only == ["industrial"]:
		print("The six industrial zone (stage 2) enemies:")
		build_industrial(write)
		_report(write)
		return
	if not os.path.isdir(PACK):
		sys.exit("Cannot find the enemy art pack %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(PACK))
	print("Patrollers A/B/C (no. 2):")
	build_walkers(write)
	print("D (no. 3) and F (no. 1):")
	build_singles(write)
	print("Boss A (boss pack no. 2):")
	build_boss(write)
	print("Turret (no. 6):")
	build_turret(write)
	print("Flying E (no. 5):")
	build_flyer(write)
	print("The six industrial zone (stage 2) enemies:")
	build_industrial(write)
	print("The six bar street (stage 3) enemies:")
	build_bar_street(write)
	print("The six basement (stage 4) enemies:")
	build_basement(write)
	_report(write)


def _report(write):
	if sb._clipped:
		print("\nContent was cut off by the canvas:")
		for line in sb._clipped[:20]:
			print("  " + line)
		sys.exit(1)
	print("\nNothing was cut off." + ("" if write else " (--check: no files written)"))


if __name__ == "__main__":
	main()
