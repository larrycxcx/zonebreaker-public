"""The layered version of stage 2 (industrial zone): drawn segment by segment and joined into a whole stage by `map_canvas.stitch()`.

Redone in 2026-10 from the user's sketch: the view still scrolls continuously sideways, but every segment is **layered** (upper / middle / ground,
layers 96 or more apart cannot be jumped, only reached by ladders or gaps), and sometimes you have to **take a detour**.

A few rules the user set after seeing the first two segments (2026-10):
- **Only one exit** (the final boss). Seven of the ten segments **force a detour** (marked [detour]), three let you **pick either of the upper and lower routes** (marked [choice]).
- **Lots of enemies, placed sensibly**: chargers (2-B ramming, 2-F self-destructing, 2-A charging on landing, 2-D charging on sight) only go on paths blocked at both ends,
  **and a path must not end in a pit** (`chasers` in `map_build.check` checks this: charging enemies used to fall into pits by themselves before reaching the player);
  where there are upper and lower layers, put more diagonal-shooting 2-Cs. At least 4 per screen (`MIN_ENEMIES`).
- **A full picture**: plenty of small objects, obstacles and traps (barrels, breakable crates, conveyors, presses, gates); no big empty stretches.

Letters: a 2-A (hangs above the top of the view and drops when you walk under it), b 2-B (rams), c 2-C (gunner, shoots diagonally), d 2-D (hammer guy),
e 2-E (helicopter, flies), f 2-F (self-destructing bot), B Boss. Rows: the upper floor is row 7, the middle row 13, the ground row 20;
enemies are written **on the row above the one under their feet**.
"""

from map_canvas import Canvas, from_png, stitch

LETTERS = {"a": "2_a", "b": "2_b", "c": "2_c", "d": "2_d", "e": "2_e", "f": "2_f", "boss": "2_boss"}
FLOATING = {"2_e", "2_boss"}
HANGING = {"2_a"}
## The ones that charge: the path under their feet must not end in a pit at either end
CHASERS = {"2_a", "2_b", "2_d", "2_f"}
MIN_ENEMIES = 4


def yard():
	"""[detour] Segment 1 "Factory gate".
	The first screen is outdoors with no enemies: two chimneys and two levels of girder walkways (teaching you to jump up).
	The second screen is two-storey factory A: enter the ground floor through the door, **the ground floor ends at a wall**, so climb the ladder to the first floor;
	the first floor is a **conveyor running backwards**, with self-destructing bots charging along it."""
	cv = Canvas(80)
	cv.ground(0, 39)
	cv.ground(40, 79, "%")
	cv.put(3, 19, "@")
	cv.fill(8, 9, 10, 19, "!")
	cv.fill(32, 33, 12, 19, "!")
	cv.floor(14, 24, 16, ":")
	cv.floor(20, 28, 12, ":")
	cv.prop("barrel_rust", 11, 20)
	cv.prop("box", 26, 20)
	cv.prop("sign", 36, 20)
	cv.prop("flag", 30, 12)
	# Factory A: roof on row 7, first floor on row 13; the bottom 4 cells of the left outer wall are the door, and the end of the ground floor (columns 78~79) is a wall
	cv.floor(38, 79, 7)
	cv.fill(40, 41, 8, 15)
	cv.floor(42, 79, 13)
	cv.belt(62, 76, 13, -1)
	cv.fill(78, 79, 14, 19)
	cv.ladder(56, 13, 20)
	cv.crates(45, 20, 1)
	cv.put(50, 19, "d")
	cv.put(66, 19, "b")
	cv.put(74, 19, "c")
	cv.barrel(72, 20)
	cv.put(62, 19, "c")
	cv.prop("screen", 42, 11)            # The monitor screen on the first floor wall (animated)
	cv.put(46, 12, "c")
	cv.put(74, 12, "f")
	cv.barrel(70, 13)
	# Roof: steel crates, railings
	cv.fill(56, 59, 5, 6, "X")
	cv.prop("barrel_rust", 66, 7)
	cv.rail(62, 76, 7)
	cv.prop("board", 62, 18)
	cv.prop("locker", 48, 11)
	cv.pipe([(22, 8), (38, 8)])
	cv.sign(1, 30, 8)
	cv.pipe([(21, 4), (39, 4)])
	cv.sign(2, 33, 4)
	return cv


def gantry():
	"""[detour] Segment 2 "Girders". The back half of factory A: the first floor exit is a **blast gate**, the ground floor is blocked by machinery.
	Outside is a settling pond, **all pits underneath**, so you can only walk the girders; above them is a higher level where gunners shoot diagonally down,
	hanging 2-As drop onto the girders and a helicopter drops bombs alongside. At the end of the girders take the ladder down to the ground."""
	cv = Canvas(80)
	cv.floor(0, 25, 7)
	cv.floor(0, 23, 13)
	cv.fill(0, 21, 14, 19, "X")         # The ground floor blocked by machinery
	cv.fill(22, 23, 14, 19)
	cv.ground(0, 23)
	cv.floor(22, 23, 8)
	cv.put(22, 9, "G")
	cv.put(8, 12, "c")
	cv.put(14, 12, "b")
	cv.barrel(10, 13)
	cv.prop("locker", 4, 11)            # Hung on the wall
	cv.prop("board", 16, 11)
	# Settling pond: pits under columns 24~55, with a few pipes standing in the pond
	cv.fill(30, 31, 15, 22, "!")
	cv.fill(44, 45, 14, 22, "!")
	cv.fill(52, 53, 16, 22, "!")
	cv.floor(24, 61, 13, ":")
	cv.floor(34, 46, 9, ":")            # The higher level: gunners stand on it and shoot down
	cv.rail(26, 32, 13)
	cv.put(40, 8, "c")
	cv.put(36, 0, "a")
	cv.put(48, 0, "a")
	cv.put(30, 4, "e")
	cv.put(54, 5, "e")
	cv.put(66, 5, "e")
	# The far bank: a low lip at the pond's edge (chargers will not fall into the pond), with the ladder landing behind it
	cv.ground(56, 79)
	cv.fill(56, 57, 18, 19)
	cv.ladder(58, 13, 20)
	cv.crates(64, 20, 2)
	cv.put(70, 19, "d")
	cv.put(76, 19, "c")
	cv.barrel(74, 20)
	cv.prop("warning", 61, 20)
	return cv


def ambush():
	"""[choice] Segment 3 "Ambush". A girder broken into three pieces above (jumpable), the ground below, **either route works**:
	above, three gunners shoot diagonally down; below, there are rammers and self-destructing bots, and two 2-As hang above the girder gaps, dropping on anyone on the ground."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(2, 24, 13, ":")
	cv.ladder(4, 13, 20)
	cv.floor(29, 50, 13, ":")
	cv.floor(55, 75, 13, ":")
	cv.ladder(72, 13, 20)
	cv.put(12, 19, "d")
	cv.put(18, 12, "c")
	cv.put(26, 0, "a")
	cv.put(36, 4, "e")
	cv.put(40, 19, "b")
	cv.put(44, 12, "c")
	cv.put(52, 0, "a")
	cv.put(64, 19, "f")
	cv.barrel(62, 20)
	cv.barrel(66, 20)
	cv.put(70, 12, "c")
	cv.put(62, 3, "e")
	cv.crates(32, 20, 1)
	cv.crates(48, 20, 2)
	cv.fill(22, 23, 14, 19, "!")
	cv.fill(58, 59, 14, 19, "!")
	cv.rail(6, 16, 13)
	cv.rail(58, 68, 13)
	return cv


def press_hall():
	"""[detour] Segment 4 "Press shop". The left half of the ground floor ends at a wall, take the ladder to the first floor: a row of three presses there,
	and underfoot another **conveyor running backwards** — you have to time your push forward. Past the presses there is a hole in the floor dropping into the right half of the ground floor,
	where a whole stack of **breakable crates** blocks the way, and you only get out by breaking them."""
	cv = Canvas(80)
	cv.floor(0, 79, 6)                  # Workshop roof
	cv.fill(0, 1, 7, 15)                # Left outer wall, the bottom 4 cells are the door
	cv.fill(78, 79, 7, 15)              # Right outer wall, the same
	cv.floor(0, 79, 13)
	cv.ground(0, 79)
	cv.fill(30, 31, 14, 19)             # The end of the ground floor's left half
	cv.ladder(24, 13, 20)
	cv.belt(32, 52, 13, -1)
	cv.put(34, 9, "P")
	cv.put(42, 9, "P")
	cv.put(50, 9, "P")
	cv.clear(58, 59, 13, 13)            # The hole in the first floor
	cv.crates(70, 20, 4)                # The right half of the ground floor: blocked by a whole stack of crates
	cv.put(8, 19, "c")
	cv.put(16, 19, "b")
	cv.put(22, 19, "d")
	cv.barrel(10, 20)
	cv.put(38, 19, "c")
	cv.barrel(40, 20)
	cv.put(56, 19, "d")
	cv.put(54, 12, "c")
	cv.put(66, 12, "c")
	cv.put(72, 12, "c")
	cv.prop("screen", 56, 18)
	cv.barrel(68, 13)
	cv.put(74, 19, "f")
	cv.prop("board", 12, 18)
	cv.prop("locker", 62, 11)
	cv.pipe([(2, 4), (14, 4)])
	cv.sign(3, 8, 4)
	cv.pipe([(17, 8), (34, 8)])
	cv.sign(4, 26, 8)
	cv.fill(56, 59, 4, 5, "X")          # Crates on the roof
	cv.rail(4, 20, 6)
	return cv


def settling():
	"""[detour] Segment 5 "Settling pond". The ground breaks into three pieces with pits 12 cells wide, too far to jump, **so the only way is up onto the high girders**,
	jumping across piece by piece. You can drop onto the small island in the middle (a gunner stands by the barrels) and climb back up by the island's ladder.
	Both pit edges have a low lip: charging enemies will not fall in by themselves."""
	cv = Canvas(80)
	cv.ground(0, 15)
	cv.fill(14, 15, 18, 19)
	cv.ground(28, 41)
	cv.ground(54, 79)
	cv.fill(54, 55, 18, 19)
	cv.floor(4, 22, 10, ":")
	cv.ladder(8, 10, 20)
	cv.floor(28, 36, 10, ":")
	cv.ladder(38, 10, 20)
	cv.floor(40, 50, 10, ":")
	cv.floor(55, 64, 10, ":")
	cv.fill(20, 21, 13, 22, "!")
	cv.fill(46, 47, 14, 22, "!")
	cv.put(18, 9, "c")
	cv.put(4, 19, "b")
	cv.put(20, 4, "e")
	cv.put(32, 19, "c")
	cv.barrel(30, 20)
	cv.put(34, 9, "c")
	cv.put(46, 9, "c")
	cv.put(48, 5, "e")
	cv.put(60, 9, "c")
	cv.put(70, 19, "d")
	cv.put(76, 19, "b")
	cv.barrel(66, 20)
	cv.crates(62, 20, 1)
	cv.rail(5, 13, 10)
	cv.rail(41, 49, 10)
	cv.prop("warning", 12, 20)
	cv.prop("warning", 56, 20)
	return cv


def alarm():
	"""[choice] Segment 6 "Alarm zone". A long shed: **inside** are self-destructing bots and rammers with barrels piled beside them (shoot a barrel and they go up with it);
	**on the roof** are gunners and a helicopter, reached by the ladder outside the shed. The two routes meet at the far end of the shed."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.ladder(2, 9, 20)
	cv.floor(4, 71, 9)
	cv.fill(4, 5, 10, 15)
	cv.fill(70, 71, 10, 15)
	cv.put(24, 19, "f")
	cv.barrel(22, 20)
	cv.barrel(26, 20)
	cv.put(38, 19, "b")
	cv.crates(32, 20, 1)
	cv.put(50, 19, "f")
	cv.barrel(48, 20)
	cv.barrel(52, 20)
	cv.crates(60, 20, 2)
	cv.fill(20, 21, 7, 8, "X")
	cv.fill(56, 57, 7, 8, "X")
	cv.put(16, 8, "c")
	cv.put(44, 8, "c")
	cv.put(34, 8, "c")
	cv.put(64, 8, "c")
	cv.put(30, 3, "e")
	cv.put(76, 19, "d")
	cv.pipe([(4, 6), (34, 6)])
	cv.sign(5, 18, 6)
	cv.rail(8, 18, 9)
	cv.rail(46, 54, 9)
	return cv


def heights():
	"""[detour] Segment 7 "Heights". The ground is blocked by a tall tower, so you need **two ladders** to reach the top: first up to the platform in the middle (gunners above shoot diagonally down),
	then up to the top. Over the other side, come down two levels of girders, with a helicopter guarding in mid-air."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(38, 43, 6, 19)              # Tower
	cv.floor(20, 46, 6)
	cv.floor(8, 24, 13)
	cv.ladder(12, 13, 20)
	cv.ladder(22, 6, 13)
	cv.floor(47, 56, 10, ":")
	cv.floor(56, 64, 14, ":")
	cv.put(6, 19, "d")
	cv.put(16, 12, "c")
	cv.put(32, 5, "c")
	cv.put(42, 5, "c")
	cv.put(28, 2, "e")
	cv.put(52, 3, "e")
	cv.put(52, 9, "c")
	cv.put(66, 19, "c")
	cv.barrel(68, 20)
	cv.put(72, 19, "b")
	cv.fill(28, 29, 4, 5, "X")
	cv.crates(30, 20, 2)
	cv.rail(26, 36, 6)
	cv.pipe([(5, 7), (11, 7)])
	cv.sign(6, 8, 7)
	return cv


def crossfire():
	"""[detour] Segment 8 "Three-layer crossfire". A bigger version of the sketch screen: the left half of the ground floor ends at a wall, take the ladder to the first floor;
	the first floor is also blocked by a wall after a press, and a hole in the floor drops back into the right half of the ground floor (gunners on one-way ledges shoot diagonally up and down),
	then climb the ladder back to the right part of the first floor."""
	cv = Canvas(80)
	cv.floor(0, 79, 7)
	cv.floor(0, 79, 13)
	cv.ground(0, 79)
	cv.fill(31, 32, 14, 19)
	cv.ladder(26, 13, 20)
	cv.put(44, 9, "P")
	cv.fill(56, 57, 8, 12)
	cv.clear(50, 51, 13, 13)
	cv.floor(40, 46, 17, "=")
	cv.ladder(66, 13, 20)
	cv.fill(78, 79, 14, 19)             # The end of the ground floor's right half: the only way is back up to the first floor
	cv.put(14, 19, "b")
	cv.put(8, 19, "c")
	cv.prop("screen", 40, 11)
	cv.put(6, 12, "c")
	cv.put(20, 12, "d")
	cv.put(36, 12, "c")
	cv.barrel(38, 13)
	cv.put(48, 12, "c")
	cv.put(42, 16, "c")
	cv.put(60, 19, "c")
	cv.barrel(62, 20)
	cv.put(72, 19, "d")
	cv.put(74, 12, "f")
	cv.barrel(70, 13)
	cv.crates(36, 20, 1)
	cv.fill(10, 13, 5, 6, "X")
	cv.fill(60, 61, 5, 6, "X")
	cv.rail(20, 34, 7)
	cv.pipe([(2, 4), (13, 4)])
	cv.sign(7, 7, 4)
	cv.pipe([(17, 8), (38, 8)])
	cv.sign(8, 30, 8)
	return cv


def narrow():
	"""[detour] Segment 9 "Narrow passage". At the end of the first floor a ladder goes down into a long, low passage, one way straight through:
	rammers, self-destructing bots and hammer guys come head-on, **two stacks of crates block the way** (you only get through by breaking them), there are two presses,
	and some of the conveyors underfoot run backwards."""
	cv = Canvas(80)
	cv.floor(0, 73, 7)
	cv.floor(0, 9, 13)
	# Above the passage is a machine room you cannot enter (sealed at both ends): from outside you can see the walls, pipes and machines inside, not one flat block
	cv.floor(10, 73, 13)
	cv.floor(10, 73, 14)
	cv.fill(10, 11, 8, 12)
	cv.fill(72, 73, 8, 12)
	cv.fill(24, 27, 10, 12, "X")
	cv.fill(44, 45, 11, 12, "X")
	cv.fill(58, 61, 11, 12, "X")
	cv.prop("board", 34, 11)
	cv.prop("locker", 52, 11)
	cv.ground(0, 79)
	cv.ladder(4, 13, 20)
	cv.belt(14, 24, 20, -1)
	cv.crates(26, 20, 3)
	cv.belt(32, 46, 20, -1)
	cv.put(38, 16, "P")
	cv.crates(52, 20, 3)
	cv.belt(56, 66, 20, 1)
	cv.put(62, 16, "P")
	cv.put(6, 12, "c")
	cv.put(12, 19, "d")
	cv.put(18, 19, "b")
	cv.put(32, 19, "f")
	cv.barrel(30, 20)
	cv.put(46, 19, "b")
	cv.put(58, 19, "f")
	cv.barrel(56, 20)
	cv.put(68, 19, "d")
	cv.put(76, 19, "b")
	cv.fill(30, 33, 5, 6, "X")
	cv.fill(50, 51, 5, 6, "X")
	cv.rail(36, 46, 7)
	cv.pipe([(5, 8), (36, 8)])
	cv.sign(9, 20, 8)
	cv.pipe([(7, 5), (34, 5)])
	return cv


def boss_room():
	"""[choice] Segment 10 "Boss area". A big open space + eight one-way platforms (two set at the boss's height — it floats in the air,
	so you have to jump up to hit it). The boss is the end."""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((6, 13), (26, 33), (46, 53), (66, 73)):
		cv.floor(c0, c1, 16, "=")
	for c0, c1 in ((16, 23), (36, 43), (56, 63)):
		cv.floor(c0, c1, 12, "=")
	cv.floor(28, 33, 8, "=")
	cv.floor(48, 53, 8, "=")
	cv.put(10, 15, "c")
	cv.put(20, 11, "c")
	cv.put(58, 10, "B")
	cv.fill(2, 3, 12, 19, "!")
	cv.fill(76, 77, 10, 19, "!")
	cv.prop("flag", 30, 8)
	cv.prop("warning", 40, 20)
	return cv


SEGMENTS = [yard, gantry, ambush, press_hall, settling, alarm, heights, crossfire, narrow, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
