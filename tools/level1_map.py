"""The layered version of stage 1 (green zone): drawn segment by segment and joined into a whole stage by `map_canvas.stitch()`.

The same design principles as stage 2 (set by the user in 2026-10):
- **Only one exit** (the final boss). Seven of the ten segments **force a detour** (marked [detour]), three let you **pick either of two routes** (marked [choice]).
- **Lots of enemies, placed sensibly**: chargers (1-D skateboarder) only go on paths blocked at both ends, and a path must not end in a pit;
  where there are upper and lower layers, put more diagonal shooters (1-B, 1-C, turret 1-G). At least 4 per screen (`MIN_ENEMIES`).
- **A full picture**: plenty of trees, grass, rocks, barrels, breakable crates; no big empty stretches.

The green zone's "indoors" is **caves**: where there is solid rock overhead, cave walls are laid (see `map_build.THEMES["green"]`).
This is stage 1, so the mechanics are taught one at a time: segment 1 is the first ladder climb, segment 3 the first cave and the first crates to break,
segment 4 the first time crossing a big pit on girders.

Letters: a 1-A (patroller, level shots only), b 1-B (bursts, shoots diagonally), c 1-C (long range, lies down, shoots diagonally),
d 1-D (skateboarder, rams), e 1-E (drone, discharges downward), f 1-F (throws grenades), g 1-G (turret, shoots diagonally), B Boss A.
Rows: the upper floor is row 7, the middle row 13, the ground row 20; enemies are written **on the row above the one under their feet**.
"""

from map_canvas import Canvas, from_png, stitch

LETTERS = {"a": "1_a", "b": "1_b", "c": "1_c", "d": "1_d", "e": "1_e", "f": "1_f", "g": "1_g",
	"boss": "1_boss"}
FLOATING = {"1_e"}
HANGING = set()
CHASERS = {"1_d"}
MIN_ENEMIES = 4


def park():
	"""[detour] Segment 1 "Park entrance". No enemies on the first screen: a few grassy steps teach jumping.
	On the second screen the ground is blocked by a rock hill taller than a jump, **the first ladder climb**: up the ladder to the hilltop and down the steps on the other side."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.put(3, 19, "@")
	cv.floor(12, 18, 16, "=")
	cv.floor(22, 28, 13, "=")
	cv.fill(30, 31, 12, 19, "!")
	cv.prop("tree_big", 6, 20)
	cv.prop("bench", 20, 20)
	cv.prop("tree_small", 34, 20)
	cv.prop("fountain", 38, 20)
	# The rock hill: columns 48~55 from row 8 all the way down to the ground, with a ladder on the left
	cv.fill(48, 55, 8, 19, "%")
	cv.ladder(46, 8, 20)
	cv.floor(58, 64, 11, "=")
	cv.floor(66, 70, 15, "=")
	cv.put(51, 7, "g")
	cv.put(60, 10, "c")
	cv.put(66, 19, "a")
	cv.put(74, 19, "b")
	cv.barrel(76, 20)
	cv.prop("tree_small", 44, 20)
	cv.prop("tree_big", 72, 20)
	return cv


def terraces():
	"""[choice] Segment 2 "Steps". Two grassy steps lead up to a long stone walkway (one-way), with the ground below it.
	**Taking the top**: two burst gunners shoot diagonally down; **taking the bottom**: a skateboarder charges (steps and stone blocks at both ends keep it in),
	with crates as cover. The two routes meet at the other end."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(6, 13, 16, 19)
	cv.fill(14, 21, 12, 19)
	cv.floor(22, 60, 12, ":")
	cv.fill(61, 66, 12, 19, "%")
	cv.fill(67, 72, 16, 19)
	cv.put(10, 15, "a")
	cv.put(20, 3, "e")
	cv.put(30, 11, "b")
	cv.put(36, 19, "d")
	cv.crates(32, 20, 1)
	cv.crates(48, 20, 1)
	cv.put(50, 11, "b")
	cv.put(56, 19, "a")
	cv.barrel(54, 20)
	cv.put(64, 11, "g")
	cv.put(76, 19, "c")
	cv.barrel(78, 20)
	cv.prop("tree_small", 2, 20)
	cv.prop("bush_big", 16, 12)
	cv.prop("tree_big", 74, 20)
	return cv


def burrow():
	"""[detour] Segment 3 "Burrow". A flat-topped hill: the cave mouth on the left is sealed with rock, so **first climb the ladder to the hilltop**;
	to the right the hilltop is blocked by a cliff reaching the sky, so the only way is to **drop into the cave** through a hole in the ground, break a whole stack of crates in the cave,
	then climb the cave's ladder back to the hilltop and go down the far side of the hill."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(3, 75, 13, 14)               # The hill (cave roof)
	cv.fill(3, 4, 15, 19, "%")           # Cave mouth sealed
	cv.fill(74, 75, 15, 19, "%")         # The right end of the cave
	cv.fill(48, 51, 0, 12, "%")          # The cliff on the hilltop, reaching all the way to the top of the view
	cv.clear(40, 41, 13, 14)             # The hole that drops into the cave
	cv.ladder(1, 13, 20)
	cv.ladder(66, 13, 20)
	cv.crates(58, 20, 3)                 # A whole stack of crates in the cave
	cv.put(10, 4, "e")
	cv.put(20, 12, "a")
	cv.put(32, 12, "b")
	cv.put(46, 12, "g")
	cv.put(24, 19, "d")
	cv.put(52, 19, "c")
	cv.barrel(54, 20)
	cv.put(64, 19, "c")
	cv.put(58, 12, "f")
	cv.put(70, 12, "a")
	cv.prop("tree_small", 14, 13)
	cv.prop("tree_big", 26, 13)
	cv.prop("tree_small", 62, 13)
	cv.prop("bush_wide", 36, 13)
	return cv


def chasm():
	"""[detour] Segment 4 "Big pit". The ground breaks for 48 cells in the middle, too far to jump: climb the ladder up the stone platform,
	then jump across a string of platforms in mid-air (some high, some low), with drones guarding overhead and gunners on the platforms."""
	cv = Canvas(80)
	cv.ground(0, 15)
	cv.ground(64, 79)
	cv.floor(4, 20, 9, ":")
	cv.floor(25, 31, 8, "=")
	cv.floor(36, 42, 10, "=")
	cv.floor(47, 53, 9, "=")
	cv.floor(58, 66, 9, ":")
	cv.ladder(8, 9, 20)
	# A few stone pillars standing in the pit (background), plus two lower stone platforms: so the space above the pit is not empty
	cv.fill(22, 23, 14, 22, "!")
	cv.fill(33, 34, 15, 22, "!")
	cv.fill(44, 45, 12, 22, "!")
	cv.fill(55, 56, 14, 22, "!")
	cv.fill(28, 33, 14, 14, ":")
	cv.fill(50, 55, 15, 15, ":")
	cv.put(30, 13, "a")
	cv.put(52, 14, "b")
	cv.put(4, 19, "a")
	cv.put(14, 8, "g")
	cv.put(28, 3, "e")
	cv.put(38, 9, "b")
	cv.put(50, 8, "c")
	cv.put(56, 3, "e")
	cv.put(62, 8, "c")
	cv.put(72, 19, "a")
	cv.put(76, 19, "f")
	cv.prop("rock_big", 1, 20)
	cv.prop("tree_small", 68, 20)
	return cv


def fortress():
	"""[detour] Segment 5 "Fort". A stone fort **with no door in the outer wall**: climb the ladder on the outer wall to the roof,
	drop through a hole in the roof into the first floor, then through the hole at the end of the first floor into the back half of the ground floor and out the back door.
	The front half of the ground floor is solid foundation."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(5, 74, 7, "%")              # Roof
	cv.fill(6, 7, 8, 19, "%")            # Front wall (no door)
	cv.floor(8, 71, 13, "%")             # First floor
	cv.fill(8, 45, 14, 19, "X")          # The front half of the ground floor is foundation
	cv.fill(46, 47, 14, 19, "%")
	cv.fill(72, 73, 8, 15, "%")          # Back wall, the bottom 4 cells are the back door
	cv.clear(30, 31, 7, 7)               # Hole in the roof
	cv.clear(60, 61, 13, 13)             # Hole in the first floor
	cv.ladder(3, 7, 20)
	cv.fill(12, 13, 5, 6, "X")
	cv.fill(44, 45, 5, 6, "X")
	cv.put(10, 3, "e")
	cv.put(20, 6, "g")
	cv.put(36, 6, "b")
	cv.put(18, 12, "c")
	cv.barrel(22, 13)
	cv.put(28, 12, "a")
	cv.put(50, 12, "a")
	cv.put(66, 12, "f")
	cv.put(56, 19, "d")
	cv.put(66, 19, "c")
	cv.barrel(64, 20)
	cv.crates(52, 20, 1)
	cv.prop("tree_big", 76, 20)
	return cv


def trench():
	"""[choice] Segment 6 "Grenadiers". A long earth embankment: **on top**, two grenadiers throw grenades down and a gunner keeps guard;
	**below**, the passage has burst gunners and skateboarders with barrels piled beside them. Climb the ladder at the left end onto the embankment, or go straight through underneath."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 74, 13, 14)
	cv.ladder(2, 13, 20)
	cv.fill(28, 29, 11, 12, "X")
	cv.fill(52, 53, 11, 12, "X")
	cv.put(16, 12, "f")
	cv.put(44, 12, "f")
	cv.put(60, 12, "c")
	cv.put(70, 12, "a")
	cv.put(30, 4, "e")
	cv.put(24, 19, "b")
	cv.barrel(26, 20)
	cv.put(34, 19, "d")
	cv.crates(40, 20, 2)
	cv.put(50, 19, "a")
	cv.crates(56, 20, 1)
	cv.put(64, 19, "b")
	cv.barrel(66, 20)
	cv.prop("tree_small", 8, 13)
	cv.prop("tree_big", 36, 13)
	cv.prop("bush_wide", 64, 13)
	cv.prop("tree_small", 77, 20)
	return cv


def islands():
	"""[detour] Segment 7 "Sky islands". The ground is broken entirely, leaving only a string of small islands floating in mid-air: jump across one by one,
	and the middle one needs a ladder climb to a higher island. The segment with the most drones."""
	cv = Canvas(80)
	cv.ground(0, 5)
	cv.fill(4, 5, 18, 19)                # A low lip at the pit's edge: a skateboarder charging here stops and does not fall in by itself
	cv.ground(74, 79)
	cv.fill(74, 75, 18, 19)
	cv.fill(8, 13, 16, 17)
	cv.fill(17, 22, 12, 13)
	cv.fill(27, 35, 12, 13)
	cv.fill(36, 41, 6, 7)
	cv.ladder(34, 6, 12)
	cv.fill(46, 51, 9, 10)
	cv.fill(56, 61, 13, 14)
	cv.fill(66, 71, 12, 13)
	cv.fill(14, 15, 15, 22, "!")
	cv.fill(52, 53, 16, 22, "!")
	cv.put(10, 15, "b")
	cv.put(20, 3, "e")
	cv.put(30, 11, "c")
	cv.put(38, 5, "g")
	cv.put(48, 3, "e")
	cv.put(48, 8, "b")
	cv.put(58, 12, "c")
	cv.put(64, 2, "e")
	cv.put(68, 11, "a")
	cv.put(76, 19, "a")
	cv.prop("tree_small", 18, 12)
	cv.prop("bush_flat", 57, 13)
	return cv


def crossfire():
	"""[detour] Segment 8 "Three-layer crossfire". The front half of the ground floor ends at a wall, take the ladder to the first floor; halfway along the first floor a wall blocks the way,
	so take the ladder to the roof, drop through the roof's hole back into the back half of the first floor, then through the first floor's hole into the back half of the ground floor and out.
	Part of the front half of the first floor is a one-way stone ledge: the gunner below can shoot diagonally up at you, and you can shoot him too."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(10, 79, 7, "%")             # Roof
	cv.fill(0, 79, 13, 14)               # First floor (also the ground floor's ceiling)
	cv.floor(6, 15, 13, ":")             # One stretch of it is one-way
	cv.clear(6, 15, 14, 14)
	cv.fill(24, 25, 15, 19, "%")         # The end of the ground floor's front half
	cv.fill(50, 51, 8, 12, "%")          # The wall halfway along the first floor
	cv.clear(62, 63, 7, 7)               # Hole in the roof
	cv.clear(74, 75, 13, 14)             # Hole in the back half of the first floor
	cv.ladder(18, 13, 20)
	cv.ladder(44, 7, 13)
	cv.put(8, 19, "a")
	cv.put(14, 19, "c")
	cv.put(12, 12, "b")
	cv.put(30, 12, "c")
	cv.put(4, 3, "e")
	cv.put(56, 6, "g")
	cv.put(66, 6, "b")
	cv.put(60, 12, "c")
	cv.barrel(62, 13)
	cv.put(70, 12, "a")
	cv.put(40, 19, "d")
	cv.put(56, 19, "f")
	cv.barrel(58, 20)
	cv.crates(66, 20, 1)
	cv.put(72, 19, "c")
	cv.fill(30, 31, 5, 6, "X")
	cv.prop("tree_small", 2, 13)
	return cv


def tunnel():
	"""[detour] Segment 9 "Narrow passage". A long, low tunnel, one way straight through: skateboarders charge head-on,
	**two stacks of crates block the tunnel** (you only get through by breaking them), and gunners have barrels piled beside them. The tunnel's roof is a tree-covered slope you cannot get onto."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 75, 13, 14)
	cv.fill(4, 7, 0, 12, "%")            # A cliff at the left end of the slope: the slope over the tunnel cannot be climbed
	cv.crates(26, 20, 3)
	cv.crates(52, 20, 3)
	cv.put(8, 19, "b")
	cv.put(14, 19, "d")
	cv.put(20, 19, "a")
	cv.put(32, 19, "c")
	cv.barrel(34, 20)
	cv.put(40, 19, "d")
	cv.put(46, 19, "b")
	cv.put(58, 19, "c")
	cv.barrel(60, 20)
	cv.put(66, 19, "d")
	cv.put(74, 19, "a")
	for c, prop in ((12, "tree_big"), (22, "bush_big"), (30, "tree_small"), (40, "tree_big"),
			(50, "bush_wide"), (58, "tree_small"), (66, "tree_big")):
		cv.prop(prop, c, 13)
	cv.put(36, 4, "e")
	cv.put(62, 4, "e")
	return cv


def boss_room():
	"""[choice] Segment 10 "Boss area". One stretch of flat ground (Boss A stands on the ground, and its ram and jumps must not reach a pit),
	with a few one-way platforms overhead: dodge its missile fans and shoot down from up high. The boss is the end."""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((8, 15), (30, 37), (52, 59), (70, 77)):
		cv.floor(c0, c1, 16, "=")
	for c0, c1 in ((18, 25), (40, 47), (60, 67)):
		cv.floor(c0, c1, 12, "=")
	cv.put(6, 19, "a")
	cv.put(20, 11, "c")
	cv.put(60, 19, "B")
	cv.fill(2, 3, 12, 19, "!")
	cv.fill(76, 77, 10, 19, "!")
	cv.prop("tree_big", 28, 20)
	cv.prop("fountain", 48, 20)
	for c, prop in ((12, "bush_big"), (24, "bench"), (36, "tree_small"), (42, "bush_wide"),
			(56, "rock_big"), (66, "tree_small"), (72, "bench")):
		cv.prop(prop, c, 20)
	return cv


SEGMENTS = [park, terraces, burrow, chasm, fortress, trench, islands, crossfire, tunnel, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
