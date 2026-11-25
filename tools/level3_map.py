"""The layered version of stage 3 (bar street): drawn segment by segment and joined into a whole stage by `map_canvas.stitch()`.

The same design principles as stages 1 and 2 (set by the user in 2026-10):
- **Only one exit** (the final boss). Seven of the ten segments **force a detour** (marked [detour]), three let you **pick either of two routes** (marked [choice]).
- **Lots of enemies, placed sensibly**: chargers (3-A lunge, 3-C leaping slash, 3-D brute) only go on paths blocked at both ends, and a path must not end in a pit;
  where there are upper and lower layers, put more diagonal-shooting 3-Bs. At least 4 per screen (`MIN_ENEMIES`).
- **A full picture**: rows of building fronts along the street (`facade_N`), bars, liquor cabinets, bar stools, kegs, barrels, breakable crates; no big empty stretches.

Bar street's "indoors" is inside buildings: where there is a floor overhead, grey brick walls are laid (see `map_build.THEMES["bar"]`).
**Building fronts only go along the open street**: they are drawn on top of the indoor walls, and placed inside a building they would cover the walls.

Letters: a 3-A (knifeman, winds up and dashes), b 3-B (gunner, shoots diagonally), c 3-C (swordsman, leaping slash), d 3-D (brute, takes less damage from the front),
e 3-E (shark mech, fires along the ground — lying down does not dodge it, only jumping does), f 3-F (cannon cart, fires grenades), B Boss 3 (unicycle mech).
Rows: the upper floor is row 7, the middle row 13, the ground row 20; enemies are written **on the row above the one under their feet**.
"""

from map_canvas import Canvas, from_png, stitch

LETTERS = {"a": "3_a", "b": "3_b", "c": "3_c", "d": "3_d", "e": "3_e", "f": "3_f", "boss": "3_boss"}
FLOATING = set()
HANGING = set()
CHASERS = {"3_a", "3_c", "3_d"}
MIN_ENEMIES = 4


def street():
	"""[detour] Segment 1 "Street corner". No enemies on the first screen: buildings along the street, a few awnings.
	On the second screen a two-storey bar takes up the whole street: enter the ground floor by the front door, **the ground floor ends at a wall**, climb the ladder to the first floor,
	go out the back door of the first floor onto the awnings and jump back down to the street."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.put(3, 19, "@")
	cv.prop("facade_1", 2, 20)
	cv.prop("facade_3", 14, 20)
	cv.prop("facade_6", 22, 20)
	cv.prop("facade_2", 31, 20)
	cv.floor(10, 15, 15, "=")
	cv.floor(20, 26, 12, "=")
	# The bar: roof on row 7, the front door at the bottom of the left wall, and the first floor part of the right wall is the back door
	cv.floor(42, 73, 7)
	cv.fill(44, 45, 8, 15, "%")
	cv.floor(46, 71, 13)
	cv.fill(70, 71, 8, 9, "%")
	cv.fill(70, 71, 14, 19, "%")
	cv.floor(72, 79, 13, "=")
	cv.ladder(64, 13, 20)
	cv.crates(56, 20, 1)
	cv.put(52, 19, "a")
	cv.put(60, 19, "e")
	cv.put(68, 19, "b")
	cv.put(50, 12, "b")
	cv.put(60, 12, "f")
	cv.barrel(62, 13)
	cv.put(76, 12, "b")
	cv.prop("counter", 47, 20)
	cv.prop("cabinet", 54, 13)
	cv.prop("sign2", 46, 7)
	return cv


def awnings():
	"""[choice] Segment 2 "Awning steps". **Above**: up a series of awnings to a long balcony, where three gunners shoot diagonally down;
	**below**: knifemen, a shark mech and swordsmen in the street. The two routes meet at the other end."""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c, name in ((2, "facade_4"), (16, "facade_5"), (30, "facade_1"), (42, "facade_2"),
			(54, "facade_3"), (62, "facade_6"), (71, "facade_1")):
		cv.prop(name, c, 20)
	cv.floor(4, 10, 16, "=")
	cv.floor(12, 18, 12, "=")
	cv.floor(20, 60, 9, "=")
	cv.put(6, 15, "f")
	cv.put(16, 19, "a")
	cv.put(24, 8, "b")
	cv.put(34, 19, "e")
	cv.put(44, 8, "b")
	cv.put(56, 8, "b")
	cv.put(50, 19, "a")
	cv.barrel(48, 20)
	cv.barrel(52, 20)
	cv.put(66, 19, "c")
	cv.crates(40, 20, 1)
	return cv


def cellar():
	"""[detour] Segment 3 "Cellar". A raised bar: climb the ladder on the porch to get in, the way right inside the bar is blocked by a wall,
	**so drop through the trapdoor in the floor into the cellar**: a shark mech fires along the ground (jump only), a stack of crates blocks the way, and once broken you climb the ladder up to the terrace and out.
	The cellar's street side has its shutter down, so it cannot be entered from the street."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(3, 75, 13, 14)               # The bar's floor (also the cellar's ceiling)
	cv.fill(3, 4, 15, 19, "%")           # The cellar's street side: shutter down
	cv.fill(74, 75, 15, 19, "%")
	cv.floor(6, 49, 7)                   # The bar's roof (the right half is the terrace, open air)
	cv.fill(48, 49, 8, 12, "%")          # The end of the way right inside the bar
	cv.clear(40, 41, 13, 14)             # Trapdoor
	cv.ladder(1, 13, 20)
	cv.ladder(66, 13, 20)
	cv.crates(58, 20, 3)
	cv.put(12, 12, "b")
	cv.put(24, 12, "d")
	cv.put(18, 12, "b")
	cv.put(34, 12, "b")
	cv.put(20, 19, "e")
	cv.put(32, 19, "c")
	cv.put(54, 19, "e")
	cv.barrel(56, 20)
	cv.put(64, 19, "a")
	cv.put(60, 12, "b")
	cv.put(70, 12, "f")
	cv.barrel(68, 13)
	cv.prop("counter", 8, 13)
	cv.prop("cabinet2", 16, 13)
	cv.prop("counter2", 28, 13)
	cv.prop("sign", 52, 13)              # The neon sign standing on the terrace
	cv.prop("facade_6", 76, 20)
	return cv


def drains():
	"""[detour] Segment 4 "Drains". The street breaks into three pieces and neither ditch can be jumped: climb the ladder onto the awnings
	and jump across one by one; the middle stretch of road is guarded by a shark mech and a cannon cart, and you can go down or not."""
	cv = Canvas(80)
	cv.ground(0, 13)
	cv.fill(12, 13, 18, 19)
	cv.ground(30, 45)
	cv.ground(62, 79)
	cv.fill(62, 63, 18, 19)
	cv.floor(2, 18, 10, "=")
	cv.floor(22, 28, 9, "=")
	cv.floor(32, 40, 11, "=")
	cv.floor(44, 50, 9, "=")
	cv.floor(54, 60, 10, "=")
	cv.floor(64, 72, 12, "=")
	cv.ladder(6, 10, 20)
	cv.ladder(34, 11, 20)
	cv.fill(20, 21, 14, 22, "!")
	cv.fill(52, 53, 13, 22, "!")
	cv.put(3, 19, "f")
	cv.put(16, 9, "b")
	cv.put(26, 8, "b")
	cv.put(38, 19, "e")
	cv.barrel(36, 20)
	cv.put(42, 19, "f")
	cv.put(48, 8, "b")
	cv.put(58, 9, "b")
	cv.put(68, 11, "b")
	cv.put(70, 19, "c")
	cv.put(76, 19, "a")
	cv.prop("facade_3", 31, 20)
	cv.prop("facade_4", 66, 20)
	return cv


def brutes():
	"""[detour] Segment 5 "Brutes". A closed shop: the ground floor shutter is down, take the ladder to the first floor;
	along a long hall on the first floor three brutes press in one after another (shot from the front they only lose half: get behind them, jump over, or throw a grenade over their heads),
	and a hole in the floor at the end of the hall drops into the back half of the ground floor, out through the back door."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(5, 73, 7)
	cv.floor(5, 73, 13)
	cv.fill(6, 7, 14, 19, "%")           # Ground floor shutter
	cv.fill(8, 47, 14, 19, "X")          # The front half of the ground floor is full of goods
	cv.fill(48, 49, 14, 19, "%")
	cv.fill(72, 73, 8, 15, "%")          # Back wall, the bottom 4 cells are the back door
	cv.clear(60, 61, 13, 13)
	cv.ladder(3, 13, 20)
	cv.put(14, 12, "b")
	cv.put(20, 12, "d")
	cv.put(28, 12, "b")
	cv.put(36, 12, "d")
	cv.barrel(38, 13)
	cv.put(52, 12, "d")
	cv.put(68, 12, "b")
	cv.put(56, 19, "e")
	cv.put(64, 19, "a")
	cv.crates(68, 20, 1)
	cv.prop("cabinet", 10, 13)
	cv.prop("counter", 44, 13)
	cv.prop("facade_6", 74, 20)
	return cv


def long_street():
	"""[choice] Segment 6 "Cannon cart avenue". **Below**, two cannon carts in the street lob grenades forward with barrels piled beside them;
	**above**, a whole row of balconies guarded by gunners and swordsmen. Climb the ladder at the left end onto the balconies, or just walk the street."""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c, name in ((0, "facade_2"), (11, "facade_5"), (24, "facade_4"), (37, "facade_1"),
			(48, "facade_5"), (61, "facade_2"), (71, "facade_3")):
		cv.prop(name, c, 20)
	cv.floor(4, 74, 10, "=")
	cv.ladder(2, 10, 20)
	cv.put(14, 9, "b")
	cv.put(20, 19, "f")
	cv.barrel(22, 20)
	cv.put(28, 19, "a")
	cv.put(34, 19, "e")
	cv.crates(40, 20, 1)
	cv.put(44, 9, "b")
	cv.put(50, 19, "f")
	cv.barrel(48, 20)
	cv.put(62, 9, "c")
	cv.put(58, 19, "e")
	cv.put(70, 19, "a")
	return cv


def rooftops():
	"""[detour] Segment 7 "Rooftops". The street is a dead end here, so climb the fire escape to the roofs and **jump across building by building**:
	the narrow alleys between buildings are pits. The buildings are empty shops whose insides you can see through the windows. Finally jump back down to the street."""
	cv = Canvas(80)
	cv.ground(0, 9)
	cv.ground(71, 79)                    # Next to the last building is the street, and dropping off the edge of the roof lands right on it
	for c0, c1, top in ((10, 24, 8), (30, 42, 6), (48, 58, 9), (64, 70, 10)):
		cv.floor(c0, c1, top)                        # Roof
		cv.fill(c0, c0 + 1, top + 1, 22, "%")        # The walls on both sides
		cv.fill(c1 - 1, c1, top + 1, 22, "%")
		cv.fill(c0 + 2, c1 - 2, 20, 22)              # The floor inside the building (cannot be entered, only seen)
	cv.ladder(8, 8, 20)
	cv.fill(26, 27, 12, 22, "!")
	cv.fill(60, 61, 14, 22, "!")
	cv.put(16, 7, "b")
	cv.put(20, 7, "f")
	cv.put(34, 5, "e")
	cv.put(38, 5, "b")
	cv.put(52, 8, "b")
	cv.put(56, 8, "f")
	cv.put(68, 9, "b")
	cv.put(66, 9, "f")
	cv.put(78, 19, "a")
	cv.prop("counter", 14, 20)
	cv.prop("cabinet", 36, 20)
	cv.prop("keg", 52, 20)
	return cv


def hotel():
	"""[detour] Segment 8 "Three-layer crossfire". A hotel: the front half of the ground floor ends at a wall, take the ladder to the first floor;
	part of the first floor is a one-way wooden floor, and the gunners downstairs can shoot diagonally up at you, and you at them;
	halfway along the first floor a wall blocks the way, so take the ladder to the roof, drop through the roof's hole back into the back half of the first floor, then through the first floor's hole into the back half of the ground floor and out."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(10, 79, 7)
	cv.fill(0, 79, 13, 14)
	cv.floor(6, 15, 13, ":")
	cv.clear(6, 15, 14, 14)
	cv.fill(24, 25, 15, 19, "%")
	cv.fill(50, 51, 8, 12, "%")
	cv.clear(62, 63, 7, 7)
	cv.clear(74, 75, 13, 14)
	cv.ladder(18, 13, 20)
	cv.ladder(44, 7, 13)
	cv.put(8, 19, "a")
	cv.put(14, 19, "b")
	cv.put(12, 12, "b")
	cv.put(30, 12, "d")
	cv.put(56, 6, "e")
	cv.put(66, 6, "b")
	cv.put(60, 12, "b")
	cv.barrel(62, 13)
	cv.put(70, 12, "f")
	cv.put(40, 19, "c")
	cv.put(56, 19, "e")
	cv.barrel(58, 20)
	cv.crates(66, 20, 1)
	cv.put(72, 19, "b")
	cv.fill(30, 31, 5, 6, "X")
	cv.prop("counter2", 34, 13)
	cv.prop("cabinet2", 26, 20)
	return cv


def alley():
	"""[detour] Segment 9 "Back alley". Under a long arcade, one way straight through: knifemen and brutes come head-on,
	a shark mech fires along the ground, and **two stacks of crates block the way** (you only get through by breaking them). The floors above the arcade cannot be reached."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 75, 13, 14)
	cv.fill(4, 7, 0, 12, "%")
	cv.crates(26, 20, 3)
	cv.crates(52, 20, 3)
	cv.put(10, 19, "e")
	cv.put(16, 19, "a")
	cv.put(22, 19, "d")
	cv.put(32, 19, "b")
	cv.barrel(34, 20)
	cv.put(40, 19, "a")
	cv.put(46, 19, "e")
	cv.put(50, 19, "c")
	cv.put(58, 19, "d")
	cv.barrel(60, 20)
	cv.put(66, 19, "b")
	cv.put(74, 19, "a")
	for c, name in ((8, "facade_4"), (21, "facade_2"), (32, "facade_6"), (41, "facade_5"),
			(54, "facade_1"), (65, "facade_3")):
		cv.prop(name, c, 13)
	return cv


def boss_room():
	"""[choice] Segment 10 "Boss area". The unicycle mech stands on the ground and rolls back and forth, and one ram can roll over three hundred:
	within 600 on either side of it there is **one stretch of solid ground with no walls** (a wall would block its sight and it would do nothing). A few awnings overhead."""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((8, 14), (28, 34), (50, 56), (68, 74)):
		cv.floor(c0, c1, 16, "=")
	for c0, c1 in ((18, 24), (38, 44), (58, 64)):
		cv.floor(c0, c1, 12, "=")
	cv.put(2, 19, "b")
	cv.put(20, 11, "b")
	cv.put(44, 19, "B")
	for c, name in ((0, "facade_5"), (13, "facade_1"), (24, "facade_4"), (37, "facade_2"),
			(48, "facade_6"), (57, "facade_5"), (70, "facade_1")):
		cv.prop(name, c, 20)
	return cv


SEGMENTS = [street, awnings, cellar, drains, brutes, long_street, rooftops, hotel, alley, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
