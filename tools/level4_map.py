"""The grid map version of stage 4 (basement, **climbed vertically**) (2026-10, the user: "redesign stage 4 by the earlier requirements too —
different routes, complex structures, more detailed art").

One whole shaft: **40 cells wide (one screen), 450 cells tall (20 screens)**, with 2 cells of solid rock wall on each side and columns 2~37 inside.
Ten segments of 45 cells (two screens) each, counted **from the bottom up**: segment 1 is the spawn segment, and the top of segment 10 is the boss area (floor on row 20 = y 320).
Each segment function gets `top` (which row of the whole map is the top row of this segment), and draws with "rows within the segment" 0~44 (44 is the bottom of the segment).

**How segments connect**: each segment's exit is a platform on its row 1, and the next segment's entrance is a one-way platform on its row 42 —
exactly 4 rows apart, reachable in one jump. A segment is 45 rows and a jump at most 4, so the string of platforms going up in a segment **has to take a few 3-row steps near the top**
(…→10→7→4→1), or the last step would be 5 rows and unjumpable (the first version got stuck at the top of segment 2 exactly like that).

The same principles as the first three stages:
- Seven of the ten segments **force a detour** (marked [detour]), three let you **pick either of two routes** (marked [choice]), with only one exit (the boss).
- In a climbing stage, a "detour" goes **sideways**: solid floors only leave a gap / ladder at one end, so you have to walk to the other end to get up;
  the view only scrolls up (`only_up`) and you can go down a dozen cells at most, so every segment goes up and never back.
- Lots of enemies, placed sensibly: the diagonal-shooting suit man 4-C and spider turret 4-E guard the floors, drones 4-D **hug the walls on both sides**
  (they do not move sideways and would block the way in the middle), and 4-As chasing up from below go in the lower half of each segment.
- A full picture: brick-walled rooms, vertical pipes, neon signs, containers, steam, barrels and breakable crates.

Letters: a 4-A (thug, chases up from below), b 4-B (cat-ear girl, platform guard), c 4-C (man in a suit, three-way gunner),
d 4-D (drone, flies at your height, a flyer), e 4-E (spider turret, short), f 4-F (skull shirt, knocks people off platforms), B the skull boss.
"""

from map_canvas import Canvas

LETTERS = {"a": "4_a", "b": "4_b", "c": "4_c", "d": "4_d", "e": "4_e", "f": "4_f", "boss": "4_boss"}
FLOATING = {"4_d", "4_boss"}
HANGING = set()
CHASERS = {"4_a"}
MIN_ENEMIES = 4
## The skull's height within its cell: row 17 plus 16 = y 288 (the laser exit is 16 below it, level with the body centre of a person standing on the row 20 floor)
FLOAT_AT = {"4_boss": 16.0}

WIDTH = 40
SEG = 45
SEGMENTS_N = 10
HEIGHT = SEG * SEGMENTS_N
## The rows used when a whole segment is a string of one-way platforms: from the entrance (42) up 4 rows each time, switching to 3 near the top, ending 3 rows below the exit (1)
CLIMB = [38, 34, 30, 26, 22, 18, 14, 10, 7, 4]


class Seg:
	"""A segment: converts "rows within the segment" to rows of the whole map, otherwise used like `Canvas`."""

	def __init__(self, cv, top):
		self.cv, self.top = cv, top

	def ledge(self, c0, c1, row, ch="="):
		self.cv.floor(c0, c1, self.top + row, ch)

	def slab(self, c0, c1, row, ch="#"):
		self.cv.floor(c0, c1, self.top + row, ch)

	def fill(self, c0, c1, r0, r1, ch="#"):
		self.cv.fill(c0, c1, self.top + r0, self.top + r1, ch)

	def ladder(self, c, top, bottom):
		self.cv.ladder(c, self.top + top, self.top + bottom)

	def put(self, c, row, ch):
		self.cv.put(c, self.top + row, ch)

	def crates(self, c, row, count=1):
		self.cv.crates(c, self.top + row, count)

	def barrel(self, c, row):
		self.cv.barrel(c, self.top + row)

	def prop(self, name, c, row):
		self.cv.prop(name, c, self.top + row)

	def entry(self):
		"""Entrance: a full-width one-way platform on row 42 of the segment (the previous segment's exit platform is 4 rows below it)."""
		self.ledge(2, 37, 42)


def sump(s):
	"""[detour] Segment 1 "Sump" (spawn). No enemies on the first screen: a few platforms teach jumping up.
	Overhead is a whole solid floor **with only one ladder at the right end** — the first ladder climb. Enemies start on the screen above the floor."""
	s.cv.ground(2, 37)
	s.put(4, 41, "@")
	s.ledge(8, 15, 38)
	s.ledge(16, 23, 34)
	s.ledge(24, 31, 30)
	s.ledge(28, 36, 26)
	s.slab(2, 37, 20)
	s.slab(2, 37, 21)
	s.ladder(32, 20, 26)
	s.ledge(4, 12, 16)
	s.ledge(12, 20, 12)
	s.ledge(20, 28, 8)
	s.ledge(26, 34, 4)
	s.ledge(30, 37, 1)
	s.put(16, 11, "c")
	s.put(24, 7, "c")
	s.put(36, 9, "d")
	s.put(27, 3, "e")
	s.put(33, 3, "e")
	s.prop("smoke", 20, 42)
	s.prop("container", 30, 42)
	s.prop("sign_hotel", 6, 30)
	s.fill(14, 15, 22, 33, "!")


def twin_shafts(s):
	"""[choice] Segment 2 "Twin shafts". A wall in the middle splits the shaft in two: **on the left** are layers of solid platforms with ladder after ladder
	(guards and knockers standing on them); **on the right** is a string of one-way platforms guarded by gunners and drones. The two sides meet at the top."""
	s.entry()
	s.fill(19, 20, 4, 37)                # The wall in the middle (4 rows left open at the bottom: both sides can be entered)
	# Left shaft: solid platforms + ladders
	s.slab(6, 17, 34)
	s.slab(2, 14, 26)
	s.slab(6, 17, 18)
	s.slab(2, 14, 10)
	s.ladder(4, 34, 42)
	s.ladder(15, 26, 34)
	s.ladder(4, 18, 26)
	s.ladder(15, 10, 18)
	s.ledge(8, 18, 7)
	s.ledge(6, 14, 4)
	# Right shaft: one-way platforms zigzagging up
	for row, (c0, c1) in zip(CLIMB, [(22, 30), (28, 36)] * 5):
		s.ledge(c0, c1, row)
	s.ledge(2, 37, 1)
	s.put(10, 33, "e")
	s.put(8, 25, "b")
	s.put(10, 17, "e")
	s.put(8, 9, "f")
	s.barrel(11, 10)
	s.put(26, 37, "c")
	s.put(36, 28, "d")
	s.put(32, 17, "c")
	s.barrel(34, 18)
	s.put(26, 13, "e")
	s.put(36, 8, "d")
	s.fill(2, 3, 35, 41, "!")
	s.prop("sign_poker", 22, 26)
	s.prop("pipe_tall", 12, 34)


def boiler_room(s):
	"""[detour] Segment 3 "Boiler room". A low room: get in through the gap in the floor on the left, with thugs, guards and a spider turret inside,
	**and a whole stack of crates blocking the ladder at the right end**, so you only climb out after breaking them. Above the roof it zigzags all the way up."""
	s.entry()
	s.ledge(2, 5, 39)                    # Only under the gap in the floor, not reaching under the floor (only a 32-tall gap is left there)
	s.slab(6, 37, 36)                    # The room's floor (columns 2~5 at the left end are the gap)
	s.fill(2, 37, 26, 28)                # Roof
	s.ladder(34, 26, 36)
	s.crates(30, 36, 4)                  # The stack in front of the ladder
	s.put(20, 41, "c")
	s.put(12, 35, "a")
	s.put(20, 35, "b")
	s.barrel(22, 36)
	s.put(26, 35, "e")
	s.prop("smoke", 8, 36)
	s.prop("pipe_bend", 16, 36)
	s.ledge(24, 32, 22)
	s.ledge(16, 24, 18)
	s.ledge(8, 16, 14)
	s.ledge(2, 10, 10)
	s.ledge(8, 20, 7)
	s.ledge(14, 26, 4)
	s.ledge(14, 37, 1)
	s.put(28, 21, "c")
	s.put(3, 16, "d")
	s.put(12, 13, "f")
	s.put(16, 6, "e")
	s.put(36, 12, "d")
	s.prop("sign_carre", 28, 14)


def vents(s):
	"""[detour] Segment 4 "Ventilation shaft". Four solid floors, **the ladders alternating right and left**, so you can only zigzag up;
	every floor has people standing on it with barrels and crates piled beside them."""
	s.entry()
	s.slab(2, 37, 36)
	s.slab(2, 37, 28)
	s.slab(2, 37, 20)
	s.slab(2, 37, 12)
	s.ladder(34, 36, 42)
	s.ladder(4, 28, 36)
	s.ladder(34, 20, 28)
	s.ladder(4, 12, 20)
	s.ledge(18, 28, 8)
	s.ledge(8, 18, 4)
	s.ledge(2, 12, 1)                    # The exit is on the left: the segment above (the freight lift shaft) only has the gap on the left open
	s.put(16, 35, "b")
	s.put(24, 35, "e")
	s.barrel(18, 36)
	s.put(20, 27, "f")
	s.put(10, 27, "c")
	s.crates(14, 28, 1)
	s.put(16, 19, "e")
	s.put(26, 19, "a")
	s.barrel(28, 20)
	s.put(24, 11, "c")
	s.put(14, 11, "b")
	s.crates(30, 12, 1)
	s.put(3, 5, "d")
	s.prop("container_moss", 30, 28)
	s.prop("smoke", 10, 20)
	s.prop("unit", 8, 12)


def lift_shaft(s):
	"""[detour] Segment 5 "Freight lift shaft". A big stack of containers sits in the middle of the shaft, **and the gap on the right is sealed at the bottom**:
	the only way is to jump up along the left, over the top of the container stack, then climb up the gap on the right. The turret and gunner in the right gap shoot at you across it."""
	s.entry()
	s.fill(12, 27, 10, 41, "X")          # The stack in the middle
	s.fill(28, 37, 30, 41)               # The bottom of the right gap sealed
	for row, (c0, c1) in zip(range(38, 9, -4), [(2, 7), (6, 11)] * 4):
		s.ledge(c0, c1, row)
	s.ledge(28, 33, 26)
	s.ledge(32, 37, 22)
	s.ledge(28, 33, 18)
	s.ledge(32, 37, 14)
	s.ledge(28, 33, 10)
	s.ledge(26, 37, 7)
	s.ledge(20, 30, 4)
	s.ledge(14, 30, 1)
	s.put(4, 37, "a")
	s.put(30, 29, "e")
	s.put(34, 21, "c")
	s.put(30, 17, "e")
	s.put(4, 21, "c")
	s.put(8, 33, "c")
	s.put(4, 29, "f")
	s.put(36, 10, "d")
	s.put(20, 9, "f")
	s.put(30, 6, "c")
	s.barrel(33, 30)
	s.prop("crane", 18, 10)
	s.prop("sign_hotel", 28, 34)


def casino(s):
	"""[detour] Segment 6 "Casino back door". You come into a long, low corridor, **with a whole stack of crates blocking it halfway**,
	and you only reach the ladder at the right end after breaking them; above is a hall hung with neon signs, with guards posted on the platforms."""
	s.ledge(2, 37, 42)                   # The corridor floor (can be jumped onto from below)
	s.fill(2, 37, 34, 36)                # Corridor roof
	s.ladder(34, 34, 42)
	s.crates(20, 42, 3)
	s.put(8, 41, "e")
	s.put(14, 41, "b")
	s.put(26, 41, "a")
	s.put(30, 41, "c")
	s.barrel(28, 42)
	s.ledge(24, 32, 30)
	s.ledge(14, 22, 26)
	s.ledge(4, 12, 22)
	s.slab(10, 24, 18, ":")
	s.ledge(20, 30, 14)
	s.ledge(28, 36, 10)
	s.ledge(18, 28, 7)
	s.ledge(10, 20, 4)
	s.ledge(6, 20, 1)
	s.put(18, 17, "b")
	s.put(8, 21, "c")
	s.put(36, 20, "d")
	s.put(24, 13, "f")
	s.put(32, 9, "e")
	s.put(3, 8, "d")
	s.prop("sign_poker", 4, 30)
	s.prop("sign_carre", 26, 22)
	s.prop("sign_hotel", 30, 6)


def subway(s):
	"""[choice] Segment 7 "Subway maintenance way". **On the left**, two long ladders against the wall, climbed in one go (no shooting while climbing);
	**on the right**, a string of one-way platforms with gunners, guards and two drones. The two routes meet at the top."""
	s.entry()
	s.slab(4, 12, 22)
	s.ladder(2, 22, 42)
	s.ladder(2, 1, 22)
	for row, (c0, c1) in zip(CLIMB, [(20, 28), (27, 35)] * 5):
		s.ledge(c0, c1, row)
	s.ledge(4, 37, 1)
	s.put(8, 21, "e")
	s.put(24, 37, "c")
	s.put(21, 37, "e")
	s.put(36, 30, "d")
	s.put(30, 25, "c")
	s.put(24, 21, "b")
	s.put(24, 13, "b")
	s.put(36, 12, "d")
	s.put(24, 6, "e")
	s.fill(16, 17, 6, 41, "!")
	s.prop("smoke", 8, 22)
	s.prop("container", 22, 42)


def sewer(s):
	"""[detour] Segment 8 "Sewer". A whole solid layer of rock **with only one ladder in the middle**; at the top is a low culvert,
	where a stack of crates blocks the ladder going up on the left, and the right is a dead end (guards and barrels). Above the culvert it goes up again."""
	s.entry()
	s.ledge(2, 10, 38)
	s.ledge(6, 16, 34)
	s.ledge(14, 26, 30)
	s.fill(2, 37, 24, 26)                # Rock layer
	s.fill(2, 37, 16, 18)                # Culvert roof
	s.ladder(19, 24, 30)
	s.ladder(3, 16, 24)
	s.crates(12, 24, 3)
	s.put(6, 37, "a")
	s.put(12, 33, "c")
	s.put(22, 29, "e")
	s.put(8, 23, "b")
	s.put(16, 23, "e")
	s.put(30, 23, "f")
	s.barrel(28, 24)
	s.barrel(33, 24)
	s.ledge(4, 12, 12)
	s.ledge(10, 20, 8)
	s.ledge(18, 30, 4)
	s.ledge(24, 37, 1)
	s.put(8, 11, "c")
	s.put(36, 8, "d")
	s.put(14, 7, "f")
	s.put(24, 3, "e")
	s.prop("grate", 24, 30)
	s.prop("pipe_moss", 30, 42)


def last_climb(s):
	"""[detour] Segment 9 "The last climb". Two floors with the ladders one right, one left; thugs chase up from below,
	every floor has gunners and turrets, and the last few platforms lead straight under the boss area."""
	s.entry()
	s.slab(2, 37, 32)
	s.slab(2, 37, 18)
	s.ladder(34, 32, 42)
	s.ladder(4, 18, 32)
	s.ledge(8, 18, 38)
	s.put(8, 41, "a")
	s.put(14, 37, "a")
	s.put(24, 41, "c")
	s.put(14, 31, "c")
	s.put(22, 31, "e")
	s.put(30, 31, "b")
	s.barrel(28, 32)
	s.crates(10, 32, 1)
	s.ledge(10, 20, 14)
	s.ledge(18, 28, 10)
	s.ledge(26, 34, 7)
	s.ledge(18, 28, 4)
	s.ledge(20, 37, 1)
	s.put(26, 17, "c")
	s.put(16, 17, "f")
	s.put(3, 12, "d")
	s.put(22, 9, "e")
	s.put(36, 4, "d")
	s.prop("smoke", 26, 18)
	s.prop("container_moss", 6, 32)


def boss_room(s):
	"""[choice] Segment 10: the lower half is the few platforms under the boss area, the upper half is the boss area — the floor on row 20 (y 320),
	with two high platforms above it and an even higher one (to dodge the laser: change layers). The skull floats on the right side."""
	s.entry()
	s.ledge(4, 14, 38)
	s.ledge(12, 22, 34)
	s.ledge(20, 30, 30)
	s.ledge(26, 36, 26)
	s.ledge(14, 24, 24)
	s.slab(2, 37, 20, ":")               # The boss area floor (one-way: can be jumped onto from below)
	s.ledge(4, 13, 16)
	s.ledge(26, 35, 16)
	s.ledge(14, 25, 12)
	s.put(8, 37, "c")
	s.put(16, 33, "e")
	s.put(34, 25, "c")
	s.put(34, 17, "B")
	s.prop("sign_carre", 18, 20)
	s.fill(2, 3, 4, 19, "!")
	s.fill(36, 37, 4, 15, "!")


SEGMENTS = [sump, twin_shafts, boiler_room, vents, lift_shaft, casino, subway, sewer, last_climb, boss_room]


def assemble():
	"""Drawn from the bottom up: segment 1 is at the very bottom. The rock walls on both sides go all the way to the top."""
	cv = Canvas(WIDTH, HEIGHT)
	cv.fill(0, 1, 0, HEIGHT - 1)
	cv.fill(38, 39, 0, HEIGHT - 1)
	for i, make in enumerate(SEGMENTS):
		make(Seg(cv, HEIGHT - SEG * (i + 1)))
	return cv.rows(), cv.props, {"pipes": [], "signs": [], "rails": cv.rails}
