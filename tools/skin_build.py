"""Generates the cyberpunk skin pack's player art from the original art pack, one directory per character (skins/cyberpunk/biker, punk, cyborg).

    python tools/skin_build.py            # regenerate all three characters
    python tools/skin_build.py cyborg     # only generate one
    python tools/skin_build.py --check    # only check whether anything is cut off by the canvas, without writing files

The source is CraftPix's "Free Guns for Cyberpunk Characters", unpacked in art_in/default/
(not in the repo: the licence forbids redistributing the source files). This script does three things:

1. **Strips the arms that come with the body**: the aiming arms are stuck on separately, so the body must not carry another pair.
   The art's `*2.png` are already stripped (Walk2 / Run2 / Jump2), but Dash, Idle1 and others have no armless version,
   so everything goes through `strip_arms()`, which does not touch a single pixel of art that already has no arms.
2. **Aligns by the shoulders**: the art is 48×48 per frame, but the running / jumping groups draw the character about 6px further right (leaning forward).
   The arms are drawn for the standing shoulder position, and copied as is they would come apart from the running body.
   So every frame is realigned by **the torso centre**, letting the arms stay fixed in one place instead of following each frame.
3. **Composites the arms**: one aim direction = back arm + gun + front arm stacked in three layers (the order cannot change:
   the back arm behind the gun, the front arm in front of it), baked into one image.

Each output frame is 56×56, **with the anchor (the point on the art matching the character's body origin) at (28, 40)**:
horizontally the torso centre, vertically putting the feet 16px below the origin (matching the player's 32px tall collider).
The left-facing images are **mirrored around the anchor's column**, so the anchors of both sets coincide exactly,
and at runtime there is no need for flip_h or a negative scale (a negative scale gets the character wrongly culled, see the pitfalls in CLAUDE.md).
"""
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "art_in", "default")
OWN = os.path.join(HERE, "..", "art_src")
SKIN = os.path.join(HERE, "..", "skins", "cyberpunk")

# Skin key → the character in the art. **The key is the character's name, not "player 1 / player 2"**:
# the look is a property of the character (stored in its record), and player 2 can pick Biker too.
# The three characters have exactly the same specs in the art pack (48×48, the same 10 arm images, the same action names), so nothing but the name has to change.
# Each death animation is in its own folder (`<character>_death.png`).
CHARACTERS = {
	"biker": "1 Biker",
	"punk": "2 Punk",
	"cyborg": "3 Cyborg",
}

# The three below are "which character is being generated now", switched by use_character().
# Globals rather than passing parameters all the way down: the script handles the same character from start to finish,
# and an extra parameter on every function would only make the already long call chain harder to read.
CHARACTER = ""
KEY = ""
OUT = ""
DEATH = ""
# Which gun in the art pack each gun look uses (the numbers in `2 Guns/`). The key is `Weapon.look`,
# and each outputs a whole set of arm images `arms_<look>_<direction>_<facing>.png`, swapped in by the visual layer when the player switches weapons.
# **Do not pick a gun that is too small**: the back arm in the art is drawn "mostly hidden by the gun", gun number 1 is only 26×7,
# and when firing diagonally that thick arm sticks out of the gun entirely, looking like a sausage hanging off the body.
# rifle    the rifle, number 4 (29×11)
# launcher the grenade launcher (the one that throws grenades), number 5 (28×16): the thick barrel sets it apart from the rifle at a glance, and it is about the same length.
# The two guns share one set of muzzle points (a gameplay rule); number 5's muzzle is at most 2.8px from them, see test_cyberpunk_skin.gd.
GUNS = {"rifle": 4, "launcher": 5}

CELL = 48          # Side length of an art frame
ARM_CELL = 32      # Side length of an arm / gun cell
# Where the arm cell sits in the character frame. Centred horizontally, **3px lower vertically**:
# centring it (8, 8) looks natural but has no basis — that way the arms grow out of the neck and the barrel lands at 74% of the height.
# The real shoulder position was measured: `Idle1` minus `Idle2` leaves exactly the arms that come with the art, whose roots are at y=26~28 in the frame;
# the front arm's (`8.png`) root is at y≈16 in its cell, so the cell has to sit at y=11 for the root to land at 27.
# Placed like this the barrel is at 66% of the height, matching the hand holding the gun in the art pack's promo image (measured at 64%).
ARM_INSET_X = (CELL - ARM_CELL) // 2
ARM_INSET_Y = 11
FRAME = 56         # Side length of an output frame
ANCHOR = (28, 40)  # The point in the output frame matching the character's body origin
# Height of the anchor in the art frame: the feet are at the bottom edge (y=48) and have to land 16px below the body origin.
SRC_ANCHOR_Y = CELL - 16
TORSO_ROWS = (14, 30)   # When measuring the torso centre, only look at these rows (head + upper body); the legs swing out when running
# The arm art is drawn for the standing shoulders, matching Idle's torso centre.
ARM_BASELINE = 13.0

# Body animations: output name → (art file, which frames to take).
# **air has only one frame**: the whole time in the air (rising, peak, falling) keeps the same pose.
# It used to be two frames switched by vertical speed, but swapping images at the peak looked awkward (2026-09 playtest),
# and plenty of side-scrolling shooters have just one airborne pose anyway. `SpriteAppearance` clamps to the last frame when taking the falling frame, so one frame works as usual.
# crouch takes the lowest frame of the crouch loop.
#
# **Walking uses the art's "run" and sprinting uses "Dash"** (changed after the 2026-09 playtest found the pace slow):
# not a single speed number changed, only the art — normal movement looks like running, and holding sprint adds a layer of afterimages.
# Only the `*2.png` in the art pack have their arms stripped (left for us to stick aiming arms on); Dash, Idle1 and others all have arms,
# so everything goes through `strip_arms()` when generating: those already without arms (Walk2/Run2/Jump2) do not have a single pixel touched.
BODIES = {
	"idle": ("Idle1", [0, 1, 2, 3]),
	"walk": ("Run2", [0, 1, 2, 3, 4, 5]),
	"run": ("Dash", [0, 1, 2, 3, 4, 5]),
	"air": ("Jump2", [1]),
}

# The two colours of the bare arms (light + dark). The face and neck are these two colours too, so it cannot be a single cut by colour;
# it has to split by connected blobs: the face blob is at y=19~25, and the arm blobs basically start from y=26 down.
SKIN_COLORS = {(163, 109, 62), (104, 60, 52)}
ARM_TOP = 26       # A blob only counts as an arm if its top is on this row or lower
# Any smaller is not an arm: armless versions also have a stray skin pixel or two (a corner of a fist and the like),
# and without this floor they would be deleted as arms, breaking "not a single pixel of art without arms is touched".
ARM_MIN = 6
# An arm raised to the chest joins the neck, so the whole blob starts from y=24 and the line above cannot catch it.
# Its signature is **thick and long**: however big, the face and neck never hang as low as ARM_DEEP.
ARM_BIG = 20
ARM_DEEP = 30
OUTLINE = (0, 0, 0)
# The speed afterimages behind the Dash frames. They spread far out sideways and have to be excluded first when measuring the torso centre, or the whole character would be pushed off.
STREAK = (255, 246, 174)

# The death animation comes from another pack in the same CraftPix series (third-party art, not in the repo just like art_in/default),
# in exactly the same format as the art pack: a row of 6 frames × 48×48, the first being Idle1 standing empty-handed.
# **It starts from frame 2**: frame 1 is standing empty-handed, and playing from it would first show a beat of "the gun suddenly gone, the character frozen";
# playing from the frame where it starts leaning back, the gun vanishing is covered by the falling motion.
# **Not aligned to the torso frame by frame**: the character falls backward, and pulling the torso back to the origin each frame would cancel the backward shift, turning it into spinning on the spot.
# So the whole group is positioned once by the torso of frame 1 (standing), and the later frames keep the artist's own placement.
DEATH_FRAMES = [1, 2, 3, 4, 5]

# Lying down and crawling are **not in the art pack** (the CraftPix set only has a kneeling pose); we drew them, and they live in art_src/ (in the repo).
# `biker_prone.png` is a row of four frames at **native resolution** (about 43×14 per frame, with blank columns between frames), used 1:1 without scaling.
# The original was handed over scaled up 9× and saved as lossy webp, and was restored by taking the most common colour at the middle of each 9px grid cell;
# for future art, **export a 1× PNG directly** and this step is unnecessary.
# **The height has rules**: every frame has to hide under the bullets of enemies shooting standing up, while being about as tall as the 12px hitbox,
# guarded frame by frame by test_cyberpunk_skin.gd.
## One prone / crawl source image per character, plus **what colour the torso is in that image** — needed to align the four frames by the torso centre.
## Characters not listed fall back to biker's (`restyle()` snaps the colours to their own palette).
##
## **The torso has to be found by colour; generic methods do not work**: aligning by the bounding box's right edge (the head), by the overall centroid, or by "most overlap between frames"
## was tried, and measured against the biker set all three were 2~3px off — enough to see the character sliding back and forth on the spot.
## What the artist expressed in the image is "this part stays still", and the only way is to follow it.
## Which colour to pick is chosen by **"which part moves least"** (the measured slide, smaller is better):
## biker  the pink of the shirt (hand-drawn original, no palette applied, the same pink in dozens of near shades, so the tolerance is large) slides 3.0px
## punk   the dark blue shirt 0.6px (the hair is pink too, so going by biker's settings would pick the head)
## cyborg the green hair 1.7px. The jumpsuit is one colour throughout with no separate shirt; the dark purple band at the waist was tried and slid 4.5px, the worst,
## and it is towards the back of the body, so aligning by it would push the whole character out of the 56px canvas
## The last number is **how many pixels in front of the origin this marker should land**, deciding where the whole group sits;
## taken so that "the average of the four frames' bounding box centres lands on the origin", which makes all three characters stand equally centred.
PRONE_ART = {
	"biker": ("biker_prone.png", (252, 60, 95), 80, 5),
	"punk": ("punk_prone.png", (55, 68, 110), 40, 3),
	"cyborg": ("cyborg_prone.png", (21, 137, 104), 40, 12),
}
PRONE = "biker_prone.png"
PRONE_TORSO = (252, 60, 95)
PRONE_TOLERANCE = 80
PRONE_STILL = 1              # Which frame to use lying still (counting from 0)
PRONE_CRAWL = [0, 1, 2, 3]   # Which frames the crawl loop uses, in what order: legs straight → knees drawn up → straight again
# The four frames are aligned by **the shirt (torso) centre**: when crawling the front half barely moves and the legs draw up, so aligning by the torso keeps the character from sliding back and forth on the spot.
# The torso sits 5px in front of the body origin, so the still frame roughly centres on the origin as a whole (head in front, feet behind, head short and feet long).
PRONE_TORSO_X = 5   # Overridden per character by PRONE_ART

# Aim direction → (arm number, which gun image, flipped vertically or not, rotation angle, position of the gun hand in the 32×32 cell, the direction bullets fly).
# Arms 1~5 are back arms (drawn behind the gun), 6~10 front arms for the same 5 directions (drawn in front of the gun).
# The gun only has level (`_1`) and diagonally down 45° (`_2`) images: diagonally up flips the diagonally down one vertically, straight up / down rotate the level one 90°.
#
# **Where the gun goes is decided by "where the hand is", do not derive it yourself**: the arms in the art do not rotate around a fixed point,
# the artist moved the whole arm for each direction, and placements derived from "the grip fixed at the cell centre" are wrong in four of the five directions.
# The hand positions were measured from Hands.psd: the `Deep_shadows` layer in the front arm group is the hand peeking out from the other side of the gun.
# **The straight-down image is the exception**: it has no such little block. In that pose the two arms are two parallel vertical bars,
# one in front of the body (`6.png`, cell x1..7) and one outside it (`1.png`, x14..19),
# **with the gun held between them** (x≈11), not hanging on either — placing it at the end of the back arm would float the gun entirely outside the body.
AIMS = {
	"down":      (1, "1", False,  90, (11.0, 25.0), (0, 1)),
	"diag_down": (2, "2", False,   0, (14.5, 24.0), (1, 1)),
	"level":     (3, "1", False,   0, (19.5, 17.0), (1, 0)),
	"diag_up":   (4, "2", True,    0, (19.0, 5.5), (1, -1)),
	"up":        (5, "1", False, -90, (16.0, 2.5), (0, -1)),
}

# Where the front grip is on the gun: 66% of the way from the stock end, then 1px further below the barrel.
# These two numbers were measured on the level image (the only one where you can tell at a glance whether it is right), and the other directions use the same.
GRIP_ALONG = 0.66
GRIP_ACROSS = 1.0

_clipped = []


# ---------------------------------------------------------------- PNG reading / writing

def read_png(path):
	data = open(path, "rb").read()
	assert data[:8] == b"\x89PNG\r\n\x1a\n", path
	pos, idat, width, height, depth, color, palette, trns = 8, b"", 0, 0, 0, 0, None, None
	while pos < len(data):
		length = struct.unpack(">I", data[pos:pos + 4])[0]
		tag = data[pos + 4:pos + 8]
		chunk = data[pos + 8:pos + 8 + length]
		if tag == b"IHDR":
			width, height, depth, color = struct.unpack(">IIBB", chunk[:10])
		elif tag == b"IDAT":
			idat += chunk
		elif tag == b"PLTE":
			palette = chunk
		elif tag == b"tRNS":
			trns = chunk
		pos += 12 + length
	assert depth == 8, "Only 8-bit colour depth is handled: %s" % path
	channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
	raw = zlib.decompress(idat)
	stride = width * channels
	rows, prev, pos = [], bytes(stride), 0
	for _ in range(height):
		filter_type = raw[pos]
		line = bytearray(raw[pos + 1:pos + 1 + stride])
		pos += 1 + stride
		for i in range(stride):
			a = line[i - channels] if i >= channels else 0
			b = prev[i]
			c = prev[i - channels] if i >= channels else 0
			if filter_type == 1:
				line[i] = (line[i] + a) & 255
			elif filter_type == 2:
				line[i] = (line[i] + b) & 255
			elif filter_type == 3:
				line[i] = (line[i] + (a + b) // 2) & 255
			elif filter_type == 4:
				p = a + b - c
				pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
				pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
				line[i] = (line[i] + pr) & 255
		rows.append(bytes(line))
		prev = rows[-1]

	pixels = []
	for line in rows:
		row = []
		for x in range(width):
			px = line[x * channels:(x + 1) * channels]
			if color == 6:
				row.append(tuple(px))
			elif color == 2:
				row.append((px[0], px[1], px[2], 255))
			elif color == 3:
				i = px[0]
				r, g, b = palette[i * 3:i * 3 + 3]
				row.append((r, g, b, trns[i] if trns and i < len(trns) else 255))
			elif color == 4:
				row.append((px[0], px[0], px[0], px[1]))
			else:
				row.append((px[0], px[0], px[0], 255))
		pixels.append(row)
	return width, height, pixels


def write_png(path, pixels):
	height, width = len(pixels), len(pixels[0])
	raw = bytearray()
	for row in pixels:
		raw.append(0)
		for r, g, b, a in row:
			raw += bytes((r, g, b, a))

	def chunk(tag, data):
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

	out = b"\x89PNG\r\n\x1a\n"
	out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
	out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
	out += chunk(b"IEND", b"")
	os.makedirs(os.path.dirname(path), exist_ok=True)
	open(path, "wb").write(out)


# ---------------------------------------------------------------- Canvas operations

def blank(width, height):
	return [[(0, 0, 0, 0)] * width for _ in range(height)]


def blit(dst, src, ox, oy, where):
	"""Lay src onto dst at (ox, oy). Anything that lands outside the canvas is noted down and reported together at the end."""
	height, width = len(dst), len(dst[0])
	for y, row in enumerate(src):
		for x, color in enumerate(row):
			if color[3] <= 8:
				continue
			dy, dx = oy + y, ox + x
			if 0 <= dy < height and 0 <= dx < width:
				dst[dy][dx] = color
			else:
				_clipped.append("%s: pixel (%d, %d) falls outside the %dx%d canvas" % (where, dx, dy, width, height))


def cut(pixels, x0, y0, width, height):
	return [row[x0:x0 + width] for row in pixels[y0:y0 + height]]


def rotate(src, degrees):
	if degrees == 0:
		return src
	height, width = len(src), len(src[0])
	if degrees == 90:    # Clockwise: facing right → facing down
		return [[src[height - 1 - x][y] for x in range(height)] for y in range(width)]
	if degrees == -90:   # Anticlockwise: facing right → facing up
		return [[src[x][width - 1 - y] for x in range(height)] for y in range(width)]
	raise ValueError(degrees)


def mirror(src):
	"""Mirror left and right around the anchor's column, with the anchor itself staying put."""
	width = len(src[0])
	out = blank(width, len(src))
	for y, row in enumerate(src):
		for x, color in enumerate(row):
			sx = 2 * ANCHOR[0] - x
			if color[3] > 8 and 0 <= sx < width:
				out[y][sx] = color
	return out


# ---------------------------------------------------------------- Generating

def strip_arms(frame):
	"""Remove the bare arms that come with the art, making room for the aiming arms. Already armless versions do not have a single pixel touched.

	A single cut by colour does not work — the face, neck and arms are the same skin colour. So the skin pixels are first split into connected blobs,
	**only the blobs starting below ARM_TOP are dropped** (the face is higher up), along with the black outline that only touches these blobs
	and no other body colour (that is the arms' own outline).
	"""
	size = len(frame)
	skin = {(x, y) for y in range(size) for x in range(size)
		if frame[y][x][3] > 8 and frame[y][x][:3] in SKIN_COLORS}
	arms, seen = set(), set()
	for start in sorted(skin):
		if start in seen:
			continue
		stack, blob = [start], []
		seen.add(start)
		while stack:
			x, y = stack.pop()
			blob.append((x, y))
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				near = (x + dx, y + dy)
				if near in skin and near not in seen:
					seen.add(near)
					stack.append(near)
		top = min(point[1] for point in blob)
		bottom = max(point[1] for point in blob)
		big_and_low = len(blob) >= ARM_BIG and bottom >= ARM_DEEP
		if len(blob) >= ARM_MIN and (top >= ARM_TOP or big_and_low):
			arms |= set(blob)
	out = [list(row) for row in frame]
	for x, y in arms:
		out[y][x] = (0, 0, 0, 0)
	for y in range(size):
		for x in range(size):
			if frame[y][x][3] <= 8 or frame[y][x][:3] != OUTLINE:
				continue
			touches_arm = touches_body = False
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if not (0 <= nx < size and 0 <= ny < size) or frame[ny][nx][3] <= 8:
						continue
					if (nx, ny) in arms:
						touches_arm = True
					elif frame[ny][nx][:3] != OUTLINE:
						touches_body = True
			if touches_arm and not touches_body:
				out[y][x] = (0, 0, 0, 0)
	return out


def torso_center(frame):
	"""The horizontal centre of this frame's torso (head + upper body). The arms are stuck on at this position."""
	left = right = None
	for y in range(TORSO_ROWS[0], TORSO_ROWS[1] + 1):
		for x, color in enumerate(frame[y]):
			if color[3] > 8 and color[:3] != STREAK:
				left = x if left is None else min(left, x)
				right = x if right is None else max(right, x)
	assert left is not None, "This frame's torso is empty"
	return (left + right) / 2.0


def place(content, anchor_x, where):
	"""Put the 48×48 content into the 56×56 output frame: the anchor_x column lines up with the anchor, and the feet with 16px below the origin."""
	out = blank(FRAME, FRAME)
	blit(out, content, ANCHOR[0] - int(round(anchor_x)), ANCHOR[1] - SRC_ANCHOR_Y, where)
	return out


def palette():
	"""The character's own palette, the most used colours first. Art we draw has to be snapped back to these colours so it does not clash with the pack's other frames."""
	_, _, pixels = read_png(os.path.join(SRC, "1 Characters", CHARACTER, "Idle1.png"))
	seen = {}
	for row in pixels:
		for color in row:
			if color[3] > 8:
				seen[color[:3]] = seen.get(color[:3], 0) + 1
	return sorted(seen, key=lambda c: -seen[c])


def prone_frames():
	"""Cut our own row of prone poses into frames at the blank columns (native resolution, not scaled)."""
	_, _, pixels = read_png(os.path.join(OWN, PRONE))
	width = len(pixels[0])
	solid = [any(row[x][3] > 8 for row in pixels) for x in range(width)]
	frames, start = [], None
	for x in range(width + 1):
		on = x < width and solid[x]
		if on and start is None:
			start = x
		elif not on and start is not None:
			frames.append(cut(pixels, start, 0, x - start, len(pixels)))
			start = None
	return frames


def restyle(art, colors):
	"""Snap to the character's own palette and **turn the dark outer outline pure black** — every character in the art pack has a black outline,
	while ours is dark purple, which after snapping to the palette would land on the hair colour, and the outline would not match the standing poses beside it."""
	height, width = len(art), len(art[0])
	out = []
	for row in art:
		out.append([(0, 0, 0, 0) if c[3] <= 8 else
			min(colors, key=lambda p: sum((p[i] - c[i]) ** 2 for i in range(3))) + (255,) for c in row])
	result = [row[:] for row in out]
	for y in range(height):
		for x in range(width):
			c = out[y][x]
			if c[3] == 0:
				continue
			edge = any(not (0 <= y + dy < height and 0 <= x + dx < width) or out[y + dy][x + dx][3] == 0
				for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
			if edge and 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] < 45:
				result[y][x] = (0, 0, 0, 255)
	return result


def torso_x(art):
	"""The horizontal centre of the torso (the colour `PRONE_TORSO`, tolerance `PRONE_TOLERANCE`).

	**It has to be measured before snapping to the palette**: after a character's palette is applied this colour may be gone entirely,
	and searching by colour would then find nothing. Alignment is about how it was drawn, not about whose colours it gets.
	"""
	limit = PRONE_TOLERANCE ** 2
	xs = [x for row in art for x, c in enumerate(row)
		if c[3] and sum((c[i] - PRONE_TORSO[i]) ** 2 for i in range(3)) <= limit]
	if not xs:
		raise SystemExit("%s: on %s the torso colour %s cannot be found; the numbers in PRONE_ART have to follow the art"
			% (CHARACTER, PRONE, PRONE_TORSO))
	return sum(xs) / len(xs)


def place_prone(art, where, middle):
	"""`middle` is the horizontal centre of this frame's shirt, measured on **the original before the palette is applied** (see torso_x)."""
	frame = blank(FRAME, FRAME)
	bottom = max(y for y, row in enumerate(art) if any(c[3] for c in row))
	# The torso lines up PRONE_TORSO_X in front of the origin, and the lowest row lands 16px below the origin (the same ground line as standing)
	blit(frame, art, ANCHOR[0] + PRONE_TORSO_X - int(round(middle)), ANCHOR[1] + 16 - 1 - bottom, where)
	return frame


def build_death(write):
	_, _, pixels = read_png(DEATH)
	standing = cut(pixels, 0, 0, CELL, CELL)
	anchor_x = torso_center(standing)       # Measured once, shared by the whole group
	right = [place(cut(pixels, i * CELL, 0, CELL, CELL), anchor_x, "death frame %d" % (i + 1)) for i in DEATH_FRAMES]
	save_strip("body_death_r.png", right, write)
	save_strip("body_death_l.png", [mirror(f) for f in right], write)


def build_prone(write):
	colors = palette()
	source = prone_frames()
	middles = [torso_x(f) for f in source]      # Measured on the original; after the palette is applied it cannot be measured
	frames = [restyle(f, colors) for f in source]
	still = [place_prone(frames[PRONE_STILL], "crouch", middles[PRONE_STILL])]
	crawl = [place_prone(frames[i], "crawl frame %d" % (i + 1), middles[i]) for i in PRONE_CRAWL]
	save_strip("body_crouch_r.png", still, write)
	save_strip("body_crouch_l.png", [mirror(f) for f in still], write)
	save_strip("body_crawl_r.png", crawl, write)
	save_strip("body_crawl_l.png", [mirror(f) for f in crawl], write)


## Where our own armless versions are: `art_src/<skin key>_<action>.png` (the same format as the art pack, a row of 48×48).
## **If it exists it is used directly, without running `strip_arms()`** — that one finds arms by skin-coloured blobs and only works for biker:
## punk's arm is wrapped in a sleeve and cyborg's is all armour, so not a single pixel matches, and left as is they end up with three arms.
## Rerunning with each character's own palette does not work either: those colours are also the torso's and legs', and the whole body would be eaten.
def own_body(name):
	path = os.path.join(OWN, "%s_%s.png" % (KEY, name))
	return path if os.path.exists(path) else None


def build_bodies(write):
	for name, (source, frames) in BODIES.items():
		mine = own_body(name)
		path = mine or os.path.join(SRC, "1 Characters", CHARACTER, source + ".png")
		_, _, pixels = read_png(path)
		right = []
		for index in frames:
			frame = cut(pixels, index * CELL, 0, CELL, CELL)
			if mine is None:
				frame = strip_arms(frame)
			right.append(place(frame, torso_center(frame), "%s frame %d" % (name, index + 1)))
		save_strip("body_%s_r.png" % name, right, write)
		save_strip("body_%s_l.png" % name, [mirror(f) for f in right], write)
		if mine is not None:
			print("    (using our own armless version art_src/%s)" % os.path.basename(mine))


# Climbing ladders (added in 2026-10): each character has a set `<name>_climb.png` in the art, 6 frames, **seen from behind**, both hands on the ladder.
# It comes with arms (the character has their back to us), so the arms are not stripped, and the visual layer hides the separately attached aiming arms while climbing.
# From behind there is no "torso column" that is easy to measure, so each frame is centred on its bounding box; the feet still land on the bottom edge.
CLIMB_FRAMES = [0, 1, 2, 3, 4, 5]


def build_climb(write):
	name = CHARACTER.split(" ", 1)[1]
	_, _, pixels = read_png(os.path.join(SRC, "1 Characters", CHARACTER, "%s_climb.png" % name))
	right = []
	for index in CLIMB_FRAMES:
		frame = cut(pixels, index * CELL, 0, CELL, CELL)
		xs = [x for row in frame for x, c in enumerate(row) if c[3] > 8]
		right.append(place(frame, (min(xs) + max(xs)) / 2.0, "climb frame %d" % (index + 1)))
	save_strip("body_climb_r.png", right, write)
	save_strip("body_climb_l.png", [mirror(f) for f in right], write)


def grip_in(gun, aim):
	"""Where the front grip lands in the image on the rotated gun (in the image's own coordinates)."""
	length = math.hypot(aim[0], aim[1])
	axis = (aim[0] / length, aim[1] / length)
	perp = (-axis[1], axis[0])
	points = [(x, y) for y, row in enumerate(gun) for x, color in enumerate(row) if color[3] > 8]
	along = [x * axis[0] + y * axis[1] for x, y in points]
	across = [x * perp[0] + y * perp[1] for x, y in points]
	a = min(along) + GRIP_ALONG * (max(along) - min(along))
	c = (min(across) + max(across)) / 2.0 + GRIP_ACROSS
	return (axis[0] * a + perp[0] * c, axis[1] * a + perp[1] * c)


def build_arms(write):
	for look, gun_number in GUNS.items():
		print("  %s (gun no. %d):" % (look, gun_number))
		build_arms_for(look, gun_number, write)


def build_arms_for(look, gun_number, write):
	hands = os.path.join(SRC, "3 Hands", CHARACTER)
	for name, (pose, variant, flip_v, degrees, hand, aim) in AIMS.items():
		frame = blank(CELL, CELL)
		_, _, back = read_png(os.path.join(hands, "%d.png" % pose))
		blit(frame, back, ARM_INSET_X, ARM_INSET_Y, "%s back arm" % name)
		_, _, gun = read_png(os.path.join(SRC, "2 Guns", "%d_%s.png" % (gun_number, variant)))
		if flip_v:
			gun = gun[::-1]
		gun = rotate(gun, degrees)
		# Make the gun's front grip land exactly on that hand
		grip = grip_in(gun, aim)
		blit(frame, gun, ARM_INSET_X + int(round(hand[0] - grip[0])), ARM_INSET_Y + int(round(hand[1] - grip[1])),
			"%s gun" % name)
		_, _, front = read_png(os.path.join(hands, "%d.png" % (pose + 5)))
		blit(frame, front, ARM_INSET_X, ARM_INSET_Y, "%s front arm" % name)
		right = place(frame, ARM_BASELINE, "arms_%s_%s" % (look, name))
		save_strip("arms_%s_%s_r.png" % (look, name), [right], write)
		save_strip("arms_%s_%s_l.png" % (look, name), [mirror(right)], write)


## How many pixels away from the arm the gun hand can be at most. In the straight-down pose the gun is held between two parallel arms, not over either of them,
## so it cannot be required to "land exactly on an arm"; 5px is loose enough, and still catches "a wrong number, the gun floating elsewhere".
HAND_REACH = 5.0


def check_hands():
	"""The measured hand has to touch one of the arms; otherwise the art changed and the numbers did not follow."""
	hands = os.path.join(SRC, "3 Hands", CHARACTER)
	for name, entry in AIMS.items():
		pose, hand = entry[0], entry[4]
		best = 1e9
		for index in (pose, pose + 5):
			_, _, arm = read_png(os.path.join(hands, "%d.png" % index))
			for y, row in enumerate(arm):
				for x, color in enumerate(row):
					if color[3] > 8:
						best = min(best, math.hypot(x - hand[0], y - hand[1]))
		if best > HAND_REACH:
			_clipped.append("%s: gun hand (%g, %g), distance to %d.png / %d.png is %.1fpx"
				% (name, hand[0], hand[1], pose, pose + 5, best))


## The portrait on the character select screen: **the art's own first idle frame as is** (the character with their own arms, no gun in hand).
## The body art used in the game will not do — its arms are stripped (see `strip_arms`), and the person in the portrait would have two empty sleeves;
## nor is there any need to stick the aiming arms back on, which would bring along a barrel sticking out of the frame, while choosing a character is about what the person looks like.
PORTRAIT_SRC = "Idle1"
PORTRAIT_FRAME = 0
## Which piece to crop (x, y, width, height in the source frame). The union of the three characters' four idle frames is x 2..22, y 13..47, with a little margin on each side.
## **All three characters use the same box**, so the three portraits line up on screen and their heights are comparable.
PORTRAIT_BOX = (2, 12, 22, 36)


def build_portrait(write):
	source = os.path.join(SRC, "1 Characters", CHARACTER, "%s.png" % PORTRAIT_SRC)
	_, height, art = read_png(source)
	left = PORTRAIT_FRAME * height + PORTRAIT_BOX[0]
	cut = blank(PORTRAIT_BOX[2], PORTRAIT_BOX[3])
	for y in range(PORTRAIT_BOX[3]):
		for x in range(PORTRAIT_BOX[2]):
			cut[y][x] = art[PORTRAIT_BOX[1] + y][left + x]
	if write:
		write_png(os.path.join(OUT, "portrait.png"), cut)
	print("  portrait.png  %d×%d (%s frame %d)" % (PORTRAIT_BOX[2], PORTRAIT_BOX[3],
		PORTRAIT_SRC, PORTRAIT_FRAME + 1))


def save_strip(name, frames, write):
	strip = blank(FRAME * len(frames), FRAME)
	for index, frame in enumerate(frames):
		blit(strip, frame, index * FRAME, 0, name)
	if write:
		write_png(os.path.join(OUT, name), strip)
	print("  %s  %d frames" % (name, len(frames)))


## Switch to a character: which folder the art is read from, where the art is written, which death animation to use.
def use_character(key):
	global CHARACTER, KEY, OUT, DEATH, PRONE, PRONE_TORSO, PRONE_TOLERANCE, PRONE_TORSO_X
	CHARACTER = CHARACTERS[key]
	KEY = key
	OUT = os.path.join(SKIN, key)
	# The death animation is in the character's own folder, the file name being the character name without the leading number: `1 Biker` → `Biker_death.png`
	DEATH = os.path.join(SRC, "1 Characters", CHARACTER, "%s_death.png" % CHARACTER.split(" ", 1)[1])
	PRONE, PRONE_TORSO, PRONE_TOLERANCE, PRONE_TORSO_X = PRONE_ART.get(key, PRONE_ART["biker"])
	if not os.path.isdir(OUT):
		os.makedirs(OUT)


def build_character(key, write):
	use_character(key)
	print("== %s (%s) ==" % (key, CHARACTER))
	print("Body (with the art's own arms stripped):")
	build_bodies(write)
	build_climb(write)
	print("Death (the character's own %s):" % os.path.basename(DEATH))
	build_death(write)
	print("Prone and crawling (our own art_src/%s, native resolution, colours snapped to this character's palette):" % PRONE)
	build_prone(write)
	print("Arms + gun:")
	check_hands()
	build_arms(write)
	print("The portrait on the character select screen (the art's original idle, with its own arms, no gun):")
	build_portrait(write)


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(SRC):
		sys.exit("Cannot find the original art pack %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(SRC))
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	for key in (only if only else CHARACTERS):
		if key not in CHARACTERS:
			sys.exit("No such character: %s (available: %s)" % (key, ", ".join(CHARACTERS)))
		build_character(key, write)
	if _clipped:
		print("\nContent was cut off by the canvas:")
		for line in _clipped[:20]:
			print("  " + line)
		sys.exit(1)
	print("\nNothing was cut off." + ("" if write else " (--check: no files written)"))


if __name__ == "__main__":
	main()
