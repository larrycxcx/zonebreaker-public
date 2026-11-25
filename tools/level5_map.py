"""The layered version of stage 5 (lab): drawn segment by segment and joined into a whole stage by `map_canvas.stitch()`.

The same design principles as the earlier stages (set by the user in 2026-10):
- **Only one exit** (the final boss "biopod"). Seven of the ten segments **force a detour** (marked [detour]), three let you **pick either of two routes** (marked [choice]).
- **Lots of enemies, placed sensibly**: chargers (scientists 5-A / 5-B once transformed, mutant 5-C, burrowing claw arm 5-E) only go on paths blocked at both ends;
  5-Fs on the ceiling hang above paths the player must take; stationary turrets 5-D guard junctions. At least 4 per screen (`MIN_ENEMIES`).
- **Mid-level boss "mutant gunner"** (set by the user in 2026-11): a sealed room in segment 6, whose door shuts when you go in, and the door ahead only opens once it is dead;
  **its death does not clear the stage**. The walls on both sides of the room reach the top of the view, so there is no way around over the roof.
- **New traps**: spikes (`^`, 2 cells wide, written on the cell above the floor), gas capsules (`K`, one is 48 tall = 3 rows:
  a single one can be jumped, **two stacked or one in a low corridor blocks the way**, and you only get through by breaking them).
- **A full picture**: cameras and cobwebs hanging under the ceilings, monitors on the walls, desks and chairs, generators, scanners, valves and pipes on the floor.

The lab's "indoors": where there is a floor overhead, grey-blue wall panels are laid (`map_build.THEMES["lab"]`).
Letters: a 5-A (scientist, throws acid flasks, transforms when hit / closed in on), b 5-B (scientist, transforms on sight), c 5-C (mutant, ground-smash shockwave),
d 5-D (stationary turret, three-round bursts, can shoot diagonally), e 5-E (claw arm buried in the ground, only digs out when you come close), f 5-F (hanging upside down from the ceiling, drips poison),
m the mid-level boss "mutant gunner", B the stage boss "biopod".
Rows: the upper floor is row 7, the middle row 13, the ground row 20; enemies are written **on the row above the one under their feet**,
and 5-F is written **on the row right below the ceiling** (`FLOAT_AT`: the origin is 20 below that cell's top edge, so the top of the mount touches the ceiling exactly).
"""

from map_canvas import Canvas, stitch

LETTERS = {"a": "5_a", "b": "5_b", "c": "5_c", "d": "5_d", "e": "5_e", "f": "5_f", "m": "5_mid", "boss": "5_boss"}
FLOATING = {"5_f", "5_boss"}
HANGING = set()
## The top of 5-F's mount is 20 above the origin (`EnemyCeilingEmitter.MOUNT`): written on the row right below the ceiling, the origin is 20 below that cell's top edge
FLOAT_AT = {"5_f": 20.0}
CHASERS = {"5_a", "5_b", "5_c", "5_e"}
MIN_ENEMIES = 4


def capsules(cv, c, row, count=1):
	"""Gas capsules: columns c~c+1, standing on the floor of row row, count stacked (one is 48 tall = 3 rows)."""
	cv.fill(c, c + 1, row - 3 * count, row - 1, "K")


def spikes(cv, c, row, pairs=1):
	"""Spikes: pairs groups starting from column c (each group 2 cells wide), standing on the floor of row row."""
	cv.fill(c, c + 2 * pairs - 1, row - 1, row - 1, "^")


def ceiling_props(cv, row, items):
	"""Things hanging under the ceiling of row row (cameras, cobwebs): the top edge of the art touches the ceiling."""
	for name, c in items:
		cv.prop(name, c, row + 2)


def entrance():
	"""[detour] Segment 1 "Entrance". No enemies on the first screen: a generator by the door and a few platforms.
	The second screen is the lab building: enter the ground floor by the front door, **the ground floor ends at a wall** (a store of gas capsules is behind it), climb the ladder to the first floor,
	where an emitter hangs from the ceiling, and go out of the first floor window onto the platforms outside and jump back down to the ground."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.put(3, 19, "@")
	cv.prop("generator", 8, 20)
	cv.prop("table", 24, 20)
	cv.prop("chair", 27, 20)
	cv.floor(14, 19, 15, "=")
	cv.floor(24, 29, 12, "=")
	# The lab building: roof on row 7, the front door at the bottom of the left wall, and the first floor part of the right wall is a window
	cv.floor(44, 75, 7)
	cv.fill(44, 45, 8, 15, "%")
	cv.floor(46, 73, 13)
	cv.fill(74, 75, 8, 9, "%")
	cv.fill(74, 75, 14, 19, "%")
	cv.floor(76, 79, 13, "=")
	cv.ladder(66, 13, 20)
	capsules(cv, 70, 20, 2)
	cv.put(52, 19, "a")
	cv.put(58, 19, "d")
	cv.put(62, 19, "a")
	cv.put(50, 12, "a")
	cv.put(56, 8, "f")
	cv.put(64, 12, "b")
	cv.put(70, 12, "a")
	cv.barrel(62, 13)
	cv.prop("monitor", 48, 11)
	cv.prop("scanner", 52, 20)
	ceiling_props(cv, 7, [("camera", 60), ("web", 48)])
	return cv


def gas_hall():
	"""[choice] Segment 2 "Gas corridor". **Above**: a long corridor with a row of emitters on the ceiling dripping poison and scientists throwing acid flasks;
	**below**: groups of spikes on the ground, buried claw arms, stationary turrets. Climb the ladder at the left end into the corridor; the two routes meet at the right end."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(4, 75, 7)
	cv.floor(4, 75, 13)
	cv.ladder(2, 13, 20)
	for c in (16, 32, 48, 64):
		cv.put(c, 8, "f")
	cv.put(24, 12, "a")
	cv.put(40, 12, "b")
	cv.put(56, 12, "a")
	cv.put(70, 12, "a")
	spikes(cv, 12, 20, 2)
	spikes(cv, 36, 20, 2)
	spikes(cv, 58, 20, 2)
	cv.put(22, 19, "e")
	cv.put(30, 19, "d")
	cv.put(48, 19, "c")
	cv.put(68, 19, "e")
	cv.barrel(28, 20)
	cv.prop("tube", 8, 13)
	cv.prop("monitor2", 34, 11)
	cv.prop("valve", 44, 20)
	ceiling_props(cv, 7, [("camera", 20), ("web2", 40), ("camera", 60)])
	ceiling_props(cv, 13, [("web", 26), ("web2", 52)])
	return cv


def tanks():
	"""[detour] Segment 3 "Incubators". Halfway along, the ground is blocked by a wall, so climb the ladder to the first floor; the first floor ends at a wall too,
	**so drop through the hole in the floor into the storeroom below**: two stacked gas capsules block the storeroom completely, and you only get out the back door after breaking them."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(10, 70, 13)                 # The first floor (also the storeroom's ceiling)
	cv.fill(38, 39, 14, 19, "%")         # The ground hits a wall here
	cv.floor(40, 57, 7)                  # The ceiling of the back half of the first floor
	cv.fill(56, 57, 8, 12, "%")          # The end of the first floor
	cv.clear(48, 49, 13, 13)             # The hole in the floor
	cv.fill(70, 71, 14, 15, "%")         # The wall above the storeroom's back door (the door is 4 cells tall)
	cv.ladder(8, 13, 20)
	capsules(cv, 62, 20, 2)
	cv.put(16, 19, "a")
	cv.put(24, 19, "d")
	cv.put(32, 19, "e")
	cv.put(18, 12, "a")
	cv.put(30, 12, "a")
	cv.put(44, 8, "f")
	cv.put(52, 12, "b")
	cv.put(44, 19, "c")
	cv.put(56, 19, "a")
	cv.put(66, 12, "d")
	cv.put(76, 19, "a")
	cv.barrel(34, 13)
	cv.prop("tube_valve", 14, 20)
	cv.prop("monitor3", 28, 18)
	cv.prop("generator", 42, 13)
	ceiling_props(cv, 7, [("camera", 50)])
	ceiling_props(cv, 13, [("web", 20), ("web2", 46)])
	return cv


def vent_shaft():
	"""[detour] Segment 4 "Settling pit". The ground breaks for a long stretch (32 cells, too far to jump), **so the only way is to climb up and step across a string of floating platforms**,
	with a row of emitters hanging under the pipe gallery overhead dripping poison onto the platforms; once across, jump back down to the ground."""
	cv = Canvas(80)
	cv.ground(0, 23)
	cv.ground(56, 79)
	cv.fill(22, 23, 18, 19)              # Pit edge: chargers cannot charge across (the ground runs on across segments, so ones charging from the left would fall in too)
	cv.fill(56, 57, 18, 19)
	cv.floor(18, 60, 3)                  # The pipe gallery (emitters hang under it)
	cv.ladder(18, 11, 20)
	cv.floor(20, 26, 11, "=")
	cv.floor(31, 36, 10, "=")
	cv.floor(41, 46, 11, "=")
	cv.floor(51, 56, 10, "=")
	cv.put(6, 19, "a")
	cv.put(12, 19, "d")
	cv.put(22, 10, "d")
	cv.put(28, 4, "f")
	cv.put(34, 9, "d")
	cv.put(38, 4, "f")
	cv.put(44, 10, "d")
	cv.put(48, 4, "f")
	cv.put(54, 9, "d")
	cv.put(64, 19, "e")
	cv.put(70, 19, "c")
	cv.put(76, 19, "d")
	cv.barrel(10, 20)
	cv.prop("valve", 2, 20)
	cv.prop("generator", 60, 20)
	ceiling_props(cv, 3, [("web", 33), ("web2", 43)])
	return cv


def turrets():
	"""[choice] Segment 5 "Turret zone". **Above**, a long steel walkway (one-way, bullets pass through both ways) with scientists on it throwing acid flasks down;
	**below**, stationary turrets on the ground fire diagonally up, with spikes in between. Take the ladder at the left end onto the walkway, or just walk the ground."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(4, 74, 11, ":")
	cv.ladder(2, 11, 20)
	cv.put(14, 10, "a")
	cv.put(8, 19, "a")
	cv.put(30, 10, "b")
	cv.put(46, 10, "a")
	cv.put(62, 10, "a")
	cv.put(20, 19, "d")
	cv.put(40, 19, "d")
	cv.put(60, 19, "d")
	spikes(cv, 28, 20, 2)
	spikes(cv, 50, 20, 2)
	cv.put(70, 19, "e")
	capsules(cv, 34, 20, 1)
	cv.barrel(42, 20)
	cv.barrel(28, 11)
	cv.prop("scanner", 8, 20)
	cv.prop("table2", 44, 20)
	cv.prop("monitor", 66, 20)
	return cv


def arena():
	"""[detour] Segment 6 "Mid-boss room". First a stretch of corridor (scientists, claw arms, turrets), then a sealed room:
	**the walls on both sides reach the top of the view** (no way around over the roof), with the doors at the foot of the walls. Once you are in, the entrance door shuts,
	and the mutant gunner is inside — only when it is dead does the exit door open. Two low platforms in the room (the laser fired from a hop is dodged on the ground; the low one by lying down)."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(18, 19, 0, 15, "%")          # The entrance wall (the bottom 4 cells are the door)
	cv.put(18, 16, "[")
	cv.floor(20, 61, 13)                 # The room's ceiling
	cv.fill(62, 63, 0, 15, "%")          # The exit wall
	cv.put(62, 16, "]")
	cv.floor(26, 31, 16, "=")
	cv.floor(50, 55, 16, "=")
	cv.put(42, 19, "m")
	cv.put(4, 19, "a")
	cv.put(10, 19, "d")
	cv.put(14, 19, "a")
	cv.put(70, 19, "a")
	cv.put(76, 19, "d")
	# No door / door2 props in the room: they are the same door frame as the room's doors, and players could not tell which one is real
	cv.prop("tube", 34, 20)
	cv.prop("tube_valve", 46, 20)
	cv.prop("monitor2", 24, 18)
	ceiling_props(cv, 13, [("camera", 30), ("camera", 52), ("web", 40)])
	cv.prop("generator", 66, 20)
	return cv


def spike_field():
	"""[detour] Segment 7 "Spike field". From here the ground is all spikes, and further on is a pit too wide to jump:
	climb the ladder to the long platforms on the first floor, jump the gaps between them while emitters on the ceiling drip down; past the pit, jump back down to the ground."""
	cv = Canvas(80)
	cv.ground(0, 29)
	cv.ground(52, 79)
	cv.fill(28, 29, 18, 19)              # Pit edges (built up on both sides)
	cv.fill(52, 53, 18, 19)
	spikes(cv, 14, 20, 6)
	cv.floor(10, 66, 5)                  # Ceiling
	cv.floor(10, 24, 12)
	cv.floor(30, 40, 11)
	cv.floor(46, 60, 12)
	cv.ladder(8, 12, 20)
	cv.put(16, 6, "f")
	cv.put(34, 6, "f")
	cv.put(54, 6, "f")
	cv.put(20, 11, "d")
	cv.put(36, 10, "d")
	cv.put(56, 11, "d")
	cv.put(4, 19, "d")
	cv.put(60, 19, "e")
	cv.put(66, 19, "c")
	cv.put(74, 19, "a")
	cv.barrel(22, 12)
	cv.prop("tube", 12, 12)
	cv.prop("monitor3", 48, 10)
	ceiling_props(cv, 5, [("camera", 26), ("web", 44)])
	return cv


def crossfire():
	"""[detour] Segment 8 "Three-layer crossfire". The front half of the ground floor ends at a wall, take the ladder to the first floor; part of the first floor is a one-way steel floor,
	and the turret downstairs can shoot diagonally up at you, and you at it; halfway along the first floor a wall blocks the way, so take the ladder to the roof,
	drop through the roof's hole back into the back half of the first floor, then through the first floor's hole into the back half of the ground floor and out."""
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
	cv.put(14, 19, "d")
	cv.put(12, 12, "a")
	cv.put(30, 12, "b")
	cv.put(38, 8, "f")
	cv.put(56, 6, "a")
	cv.put(66, 6, "d")
	cv.put(60, 12, "a")
	cv.put(70, 8, "f")
	cv.put(40, 19, "e")
	cv.put(56, 19, "c")
	cv.barrel(58, 20)
	capsules(cv, 66, 20, 1)
	cv.put(72, 19, "a")
	cv.prop("generator", 28, 20)
	cv.prop("monitor", 34, 11)
	ceiling_props(cv, 7, [("camera", 30), ("web", 58)])
	return cv


def corridor():
	"""[detour] Segment 9 "Isolation passage". A low passage (3 cells tall, a single gas capsule fills it), one way straight through:
	**two gas capsules block the way** (you only get through by breaking them), buried claw arms and mutants come head-on, with spikes in between.
	The passage is too low for emitters to hang in (people would run into them). The floors above the passage cannot be reached."""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 75, 15, 16)               # The passage roof: rows 17~19 below it, 3 cells tall
	cv.fill(4, 7, 0, 14, "%")
	capsules(cv, 26, 20, 1)
	capsules(cv, 52, 20, 1)
	cv.put(12, 19, "e")
	cv.put(16, 19, "d")
	cv.put(20, 19, "a")
	cv.put(34, 19, "c")
	cv.put(40, 19, "a")
	cv.put(46, 19, "e")
	cv.put(60, 19, "a")
	cv.put(66, 19, "b")
	cv.put(72, 19, "c")
	spikes(cv, 38, 20, 1)
	cv.barrel(32, 20)
	cv.barrel(58, 20)
	for c, name in ((12, "monitor2"), (40, "monitor"), (64, "monitor2")):
		cv.prop(name, c, 13)
	cv.prop("valve", 22, 15)
	cv.prop("generator", 44, 15)
	return cv


def boss_room():
	"""[choice] Segment 10 "Boss area". The biopod floats in the air, and its sweeping laser presses all the way down to the chest of a person standing on the ground:
	**one stretch of flat ground with no walls** (walls block the laser and its sight), with a few one-way platforms overhead (anyone standing on them during a sweep has to jump down)."""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((8, 14), (28, 34), (50, 56), (68, 74)):
		cv.floor(c0, c1, 15, "=")
	for c0, c1 in ((18, 24), (38, 44), (58, 64)):
		cv.floor(c0, c1, 11, "=")
	cv.put(2, 19, "a")
	cv.put(20, 10, "a")
	cv.put(54, 10, "B")
	cv.prop("generator", 2, 20)
	cv.prop("scanner", 40, 20)
	cv.prop("valve", 64, 20)
	return cv


SEGMENTS = [entrance, gas_hall, tanks, vent_shaft, turrets, arena, spike_field, crossfire, corridor, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
