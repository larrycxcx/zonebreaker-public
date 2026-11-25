"""Generates stages from grid maps (2026-10, layered stages).

The direction set by the user's sketch: the view still scrolls continuously sideways, but the scene is **layered, separated by solid floors, connected by ladders and gaps**,
and sometimes you have to take a detour to solve it. The old `level_build.py` was "one long ground + floating platforms" and could not express that structure,
so it switched to **one continuous grid map per stage**: a cell is 16 pixels, 23 rows tall (one screen), and the width is the length of the whole stage,
joined segment by segment (of varying widths).

    #   solid: steel plate (ground, walls, floors)
    X   solid: steel crate (looks different, same rules as #)
    %   solid: red warning stripes (the kind on the ground)
    ~   solid: conveyor running right (`BELT_SPEED`). People and enemies standing on it are carried along
    -   solid: conveyor running left
    K   breakable crate (2 cells wide): as many crates are stacked as there are K rows (one is 24 tall, converted by `CRATE_H`), 4 shots each.
        Pathfinding **treats it as absent** (once broken you can pass); it blocks bullets and sight, and enemies can hide behind it
    O   barrel: explodes with one shot (grenade-style explosion), hurting nearby enemies and the player too. Does not block the way
    ^   spikes (2 cells wide, written on the cell above the floor): extend and retract to a rhythm, and hurt on contact while extended. Does not block the way (stage 5)
    !   a vertical red and white pipe (2 cells wide, decoration only, does not block people, drawn on the background layer): the chimneys at the top left of the promo art
    =   one-way platform: people can stand on it from above, down + jump drops through it, bullets pass through
    :   one-way platform: a girder walkway with supports (looks different, same rules as =)
    H   ladder (2 cells wide). The row of its topmost cell is the top of the ladder: that floor gets a hole here, covered with an invisible one-way lid
    P   hydraulic press (top-left corner, takes 2×4 cells, hanging under the ceiling directly above)
    G   blast gate (top-left corner, takes 2×4 cells; above it has to be solid all the way to the top — otherwise you would jump over)
    [ ] the mid-boss room's entrance door / exit door (top-left corner, 2×4 cells, sealed to the top like the gate): the entrance door is open and only shuts once everyone is in,
        the exit door is shut and only opens once the mid-boss is dead. Pathfinding treats both as open
    @   spawn (feet on the cell below)
    >   exit (feet on the cell below): the end the self-check looks for. A segment without a boss must have one —
        without it "anywhere standable in the rightmost column" counts, and when the middle layer runs to the right edge you "get there" without climbing the ladder
    B   boss (feet on the cell below)
    a~z enemies (a lookup table per stage), feet on the cell below
    .   empty (a space counts as empty too)

**Layer height**: a jump is 87, safely up 4 cells (64) at most. So two floors 6 cells (96) or more apart **cannot be jumped**,
only reached by ladders or gaps — this is the skeleton of layered stages. The usual three layers: the upper floor on row 7 (y 112), the middle on row 13 (y 208),
the ground on row 20 (y 320, the same height as the old stages). The middle passage has 80 of headroom, and a press (64) hangs just under the upper floor.

**Self-check** (`check()`) finds paths on the cells: starting from the spawn, where can you get by "walking, jumping, dropping, passing through one-way platforms, climbing ladders",
and the exit (somewhere standable in the rightmost column, or the boss) must be reachable. It also checks that both ends of ladders meet floors, presses have a ceiling above,
gates are sealed above, and enemies stand on surfaces.

    python tools/level_build.py demo     # generate the sketch segment (scenes/map_demo.tscn) and screenshot it for the user
"""
import os

import level_build as lb

CELL = 16
## All solid in collision, they only look different (`TileArt` picks tiles by material).
SOLIDS = "#X%~-"
## Conveyors: character → speed (px/s, positive to the right). The player walks at 180, and a belt at 70 means "a bit slower walking against it, a bit faster with it"
BELT_SPEED = 70.0
BELTS = {"~": BELT_SPEED, "-": -BELT_SPEED}
CRATE_H = 24
## Which scene breakable things use (crates in the industrial zone and the like; gas capsules in the lab, 48 tall, one per three rows of `K`).
CRATE_SCENE = "res://scenes/trap_crate.tscn"
SPIKE_SCENE = "res://scenes/trap_spikes.tscn"
## The bottom of the spike frames is a few pixels below the floor surface: the 4 rows of the base are sunk into it (`SpikeTrap.SURFACE`).
SPIKE_SINK = 4
BARREL_H = 22
## Two looks for one-way platforms (same rules).
ONE_WAYS = "=:"
ROWS = 23
GROUND_ROW = 20
## How many cells a jump safely climbs at most, and how many it spans sideways at most (from the numbers in `player.gd`: jump 87 tall, widest pit 104).
JUMP_ROWS = 4
JUMP_COLS = 6
## Jumping down across a gap, how many cells lower still counts (any lower is "dropping", already covered by the walk-off-the-edge path)
DROP_ROWS = 6
## How tall a person is (cells): this many cells above where they stand have to be empty.
BODY_ROWS = 2
TRAP_COLS = 2
TRAP_ROWS = 4
LADDER_COLS = 2
## No enemies on the spawn screen (44 cells = 704 pixels, the same as `SAFE_START` 700 in horizontal stages).
SAFE_COLS = 44
## How tall a screen is (cells): 360 / 16. Vertical stages count enemies screen by screen with it and use it to find the spawn screen.
SCREEN_ROWS = 22.5
## No enemies within this distance of the spawn in vertical stages (pixels).
SAFE_RADIUS = 420.0


class MapLevel:
	"""Read a grid map into geometry: solid rects, one-way platforms, ladders, traps, enemies, spawn."""

	def __init__(self, rows, letters, scenes, stand_of, floating=(), hanging=(), float_at=None):
		"""`letters`: lowercase letters in the map → enemy types (`"c": "2_c"`, the boss uses the key `"boss"`);
		`scenes`: enemy type → scene path (that is the `ENEMIES_x` table of each stage in `level_build.py`)."""
		width = max(len(r) for r in rows)
		self.grid = [r.ljust(width, ".").replace(" ", ".") for r in rows]
		## How tall: exactly one screen (23 rows) for horizontal stages; a **vertical stage** (stage 4) is one whole shaft, hundreds of rows (2026-10).
		self.height = len(self.grid)
		if self.height < ROWS:
			raise SystemExit("A grid map needs at least %d rows (it has %d)" % (ROWS, self.height))
		self.vertical = self.height > ROWS
		self.width = width
		self.letters = letters
		self.enemy_scenes = scenes
		## Flyers (helicopters, floating bosses): placed in the middle of the cell, with no ground needed below.
		self.floating = set(floating)
		## Those hanging above the top of the view waiting to drop (stage 2's 2-A): whatever row they are written on, they are placed above the view (`lb.HANG_Y`).
		self.hanging = set(hanging)
		## How high a flyer sits in its cell (the middle, 8, by default). Stage 4's skull has to be exactly at 288: the laser exit lines up with a person standing on the floor
		self.float_at = float_at or {}
		self.stand_of = stand_of
		self.solids = []      # (name, x, y, width, height)   unit: pixels
		self.ledges = []      # (name, x, y, width)
		self.ladders = []     # (name, centre x, top y, height)
		self.presses = []     # (name, x, y, ceiling y, offset in seconds)
		self.gates = []       # (name, x, y, offset in seconds)
		self.doors = []       # (name, x, y, is it the exit door)
		self.belts = []       # (name, x, y, width, height, speed)
		self.crates = []      # (name, top-left x, top-left y)
		self.barrels = []     # (name, centre x, centre y)
		self.spikes = []      # (name, top-left x, top-left y, offset in seconds)
		self.enemies = []     # (name, type, x, y)
		self.props = []
		self.spawn = None
		self.exit_cell = None
		self.boss_cell = None
		self._read()

	def at(self, r, c):
		if c < 0 or c >= self.width:
			return "#"          # Walls at both ends of the stage
		if r < 0:
			return "."
		if r >= self.height:
			return "#"
		return self.grid[r][c]

	def solid(self, r, c):
		return self.at(r, c) in SOLIDS

	def _read(self):
		counts = {}

		def name(prefix):
			counts[prefix] = counts.get(prefix, 0) + 1
			return "%s%d" % (prefix, counts[prefix])

		# Solid: find the horizontal runs in each row first, then merge runs that are the same above and below into one block (hundreds fewer nodes)
		# Each conveyor is its own block (each with its own speed), not merged with other solids
		plain = SOLIDS.translate({ord(b): None for b in BELTS})
		runs = {}
		for r in range(self.height):
			c = 0
			while c < self.width:
				ch = self.grid[r][c]
				if ch in plain:
					start = c
					while c < self.width and self.grid[r][c] in plain:
						c += 1
					runs.setdefault((start, c), []).append(r)
				elif ch in BELTS:
					start = c
					while c < self.width and self.grid[r][c] == ch:
						c += 1
					self.belts.append((name("Belt"), start * CELL, r * CELL, (c - start) * CELL, CELL, BELTS[ch]))
				else:
					c += 1
		for (start, end), rows in sorted(runs.items(), key=lambda kv: (kv[1][0], kv[0][0])):
			block = [rows[0]]
			for r in rows[1:] + [None]:
				if r is not None and r == block[-1] + 1:
					block.append(r)
					continue
				self.solids.append((name("Solid"), start * CELL, block[0] * CELL,
					(end - start) * CELL, len(block) * CELL))
				if r is not None:
					block = [r]
		# One-way platforms: each horizontal run in a row
		for r in range(self.height):
			c = 0
			while c < self.width:
				if self.grid[r][c] in ONE_WAYS:
					start = c
					while c < self.width and self.grid[r][c] in ONE_WAYS:
						c += 1
					self.ledges.append((name("Ledge"), start * CELL, r * CELL, (c - start) * CELL))
				else:
					c += 1
		# Ladders: vertically connected H (2 cells wide, identified by the left column)
		seen = set()
		for c in range(self.width):
			for r in range(self.height):
				if self.grid[r][c] != "H" or (r, c) in seen:
					continue
				if self.at(r, c - 1) == "H" and (r, c - 1) in seen:
					continue
				bottom = r
				while self.at(bottom + 1, c) == "H":
					bottom += 1
				for rr in range(r, bottom + 1):
					seen.add((rr, c))
					seen.add((rr, c + 1))
				self.ladders.append((name("Ladder"), c * CELL + LADDER_COLS * CELL / 2.0, r * CELL,
					(bottom + 1 - r) * CELL))
		# Crates: vertically connected K (2 cells wide, identified by the left column), stacked from the bottom up
		seen = set()
		for c in range(self.width):
			for r in range(self.height):
				if self.grid[r][c] != "K" or (r, c) in seen:
					continue
				if (r, c - 1) in seen:
					continue
				bottom = r
				while self.at(bottom + 1, c) == "K":
					bottom += 1
				for rr in range(r, bottom + 1):
					seen.add((rr, c))
					seen.add((rr, c + 1))
				floor_y = (bottom + 1) * CELL
				for k in range(max(1, (bottom + 1 - r) * CELL // CRATE_H)):
					self.crates.append((name("Crate"), c * CELL, floor_y - CRATE_H * (k + 1)))
		# Traps, enemies, spawn, boss
		press_index = 0
		for r in range(self.height):
			for c in range(self.width):
				ch = self.grid[r][c]
				feet = (r + 1) * CELL
				x = c * CELL + CELL / 2.0
				if ch == "P":
					ceiling = r
					while ceiling > 0 and not self.solid(ceiling - 1, c):
						ceiling -= 1
					self.presses.append((name("Press"), c * CELL, r * CELL, ceiling * CELL, 0.45 * press_index))
					press_index += 1
				elif ch == "G":
					self.gates.append((name("Gate"), c * CELL, r * CELL, 0.0))
				elif ch in "[]":
					self.doors.append((name("ArenaDoor"), c * CELL, r * CELL, ch == "]"))
				elif ch == "O":
					self.barrels.append((name("Barrel"), x, feet - BARREL_H / 2.0))
				elif ch == "^" and self.at(r, c - 1) != "^":
					# Two cells wide, identified by the left cell; a row of neighbours is offset in rhythm, so the openings come one after another
					phase = 0.35 * (len(self.spikes) % 4)
					self.spikes.append((name("Spikes"), c * CELL, feet + SPIKE_SINK - 32, phase))
				elif ch == "@":
					self.spawn = (x, feet - lb.STAND)
				elif ch == ">":
					self.exit_cell = (r + 1, c)
				elif ch == "B" or ch.islower():
					kind = self.letters.get("boss" if ch == "B" else ch)
					if kind is None:
						raise SystemExit("Enemy letter %r in the grid map is not in the table" % ch)
					label = name(lb.enemy_label(kind) + "-")
					if kind in self.hanging:
						y = lb.HANG_Y
					elif kind in self.floating:
						y = r * CELL + self.float_at.get(kind, CELL / 2.0)
					else:
						y = feet - self.stand_of(kind)
					self.enemies.append((label, kind, x, y))
					if ch == "B":
						self.boss_cell = (r, c)

	# ------------------------------------------------------------ Pathfinding

	def body_free(self, r, c):
		"""Feet on the cell in row r, the body taking BODY_ROWS cells above it: those cells must not be solid."""
		return all(not self.solid(r - k, c) for k in range(1, BODY_ROWS + 1))

	def supports(self, r, c):
		return self.solid(r, c) or self.at(r, c) in ONE_WAYS or self._ladder_top(r, c)

	def _ladder_top(self, r, c):
		return self.at(r, c) == "H" and self.at(r - 1, c) != "H"

	def standable(self, r, c):
		# Below the bottom row of the map counts as solid (you cannot fall out), but **you cannot stand on it** — otherwise pit bottoms would become a walkable path
		# (once jumping down was added, the pathfinder walked across stage 1's big pit along its bottom, and with the ladder removed the self-check still passed)
		return 0 <= c < self.width and r < self.height and self.supports(r, c) and self.body_free(r, c)

	def _land(self, r, c):
		"""Falling from row r (body from r upward), which row it lands on (the first standable surface). Falling out of the map gives None."""
		while r < self.height:
			if self.solid(r - 1, c):
				return None   # The body is stuck in something solid, which does not count
			if self.supports(r, c):
				return r
			r += 1
		return None

	def is_pit(self, r, c):
		"""Walking from row r into column c (where you cannot stand): is it a pit that drops out of the stage?
		If the body is blocked by something solid it is a wall, not a pit; if you can land on any surface below (even a lower layer) it is not a pit either."""
		if not self.body_free(r, c):
			return False
		return not any(self.supports(rr, c) for rr in range(r, self.height))

	def moves(self, r, c):
		out = []
		# Walk: one cell left or right, still standable in the same row
		for dc in (-1, 1):
			if self.standable(r, c + dc):
				out.append((r, c + dc))
			elif 0 <= c + dc < self.width and self.body_free(r, c + dc):
				# Walk off the edge: fall down the neighbouring column
				land = self._land(r + 1, c + dc)
				if land is not None:
					out.append((land, c + dc))
		# Drop through a one-way platform: standing on =, press down + jump
		if self.at(r, c) in ONE_WAYS:
			land = self._land(r + 1, c)
			if land is not None:
				out.append((land, c))
		# Jump: up at most JUMP_ROWS cells and sideways at most JUMP_COLS cells; nothing solid in the space overhead.
		# You can also **jump down onto a lower platform** (at most DROP_ROWS cells lower; the lower you land the longer you are in the air and the further you go sideways, so using JUMP_COLS is conservative) —
		# the first version only counted level and upward jumps, so jumping down one level of platforms across a pit counted as "unreachable" (the string of platforms in mid-air in stage 1)
		for up in range(-DROP_ROWS, JUMP_ROWS + 1):
			for dc in range(-JUMP_COLS, JUMP_COLS + 1):
				tr, tc = r - up, c + dc
				if (up == 0 and abs(dc) <= 1) or not self.standable(tr, tc):
					continue
				if self._arc_clear(r, c, tr, tc):
					out.append((tr, tc))
		# Ladders: at the bottom / top of a ladder, the two ends connect
		for name, x, top, height in self.ladders:
			lc = int((x - CELL) // CELL)
			if c not in (lc, lc + 1):
				continue
			top_row = int(top // CELL)
			bottom_row = int((top + height) // CELL)
			if r == bottom_row:
				out.append((top_row, c))
			elif r == top_row:
				out.append((bottom_row, c))
		return out

	def _arc_clear(self, r, c, tr, tc):
		"""Jumping from (r, c) to (tr, tc): neither the rising stretch (straight above the start, up to the peak) nor the falling stretch may hit anything solid.
		One-way platforms do not block jumping up.

		The route is counted in three parts: the start column rising from the feet to the peak, crossing sideways at the peak, and the end column falling from the peak to the landing cell.
		The peak is at least 1 cell higher than both ends and at most `JUMP_ROWS` cells above the start — try each of these heights, and if any works it is fine,
		so **you can jump over obstacles lower than the peak** (crates on a roof, the low lip at a pit edge) and also land **on top of** a crate
		(the first version required the whole rectangle to be empty, so the crate you land on blocked itself)."""
		lo, hi = min(c, tc), max(c, tc)
		low = min(r, tr) - 1
		for peak in range(low, min(low, r - JUMP_ROWS - 1) - 1, -1):
			top = peak - BODY_ROWS
			path = [(rr, c) for rr in range(top, r)] + [(rr, tc) for rr in range(top, tr)]
			path += [(rr, cc) for rr in range(top, peak + 1) for cc in range(lo, hi + 1)]
			if not any(self.solid(rr, cc) for rr, cc in path):
				return True
		return False

	def reachable(self):
		if self.spawn is None:
			return set()
		sr = int((self.spawn[1] + lb.STAND) // CELL)
		sc = int(self.spawn[0] // CELL)
		seen = {(sr, sc)}
		frontier = [(sr, sc)]
		while frontier:
			here = frontier.pop()
			for nxt in self.moves(*here):
				if nxt not in seen:
					seen.add(nxt)
					frontier.append(nxt)
		return seen


def check(level, safe_cols=SAFE_COLS, chasers=(), min_enemies=0):
	"""`chasers`: the kinds that charge (rammers, self-destructors, those that charge on landing) — the path under their feet **must not end in a pit** at either end:
	what the user saw in playtesting, "charging enemies fall into pits by themselves before reaching me".
	`min_enemies`: outside the spawn screen, at least this many enemies per screen (40 cells) — no big empty stretches of just running forward."""
	problems = []
	if level.spawn is None:
		problems.append("No spawn (@)")
		return problems
	sr = int((level.spawn[1] + lb.STAND) // CELL)
	if not level.standable(sr, int(level.spawn[0] // CELL)):
		problems.append("Nothing to stand on under the spawn")
	seen = level.reachable()
	# The end: in front of the boss (for a floating boss, the standable area under it), or an exit marked >
	if level.boss_cell is not None:
		br, bc = level.boss_cell
		# Only the surfaces **within one screen** below it count (in a shaft "below" runs all the way to the spawn; the first version counted it like that, and walking anywhere on the right half "got there")
		goal = {(r, cc) for r in range(br + 1, min(level.height, br + 1 + int(SCREEN_ROWS)))
			for cc in range(bc - 12, bc + 13) if level.standable(r, cc)}
	elif level.exit_cell is not None:
		goal = {level.exit_cell}
	else:
		problems.append("No end: either place a boss (B) or mark an exit (>)")
		goal = set()
	if goal and not goal & seen:
		problems.append("The end cannot be reached from the spawn (%s)" % ("Boss" if level.boss_cell else "exit >"))
	# Ladders: both ends have to meet standable surfaces
	for name, x, top, height in level.ladders:
		c = int((x - CELL) // CELL)
		bottom_row = int((top + height) // CELL)
		if not level.solid(bottom_row, c) and level.at(bottom_row, c) not in ONE_WAYS:
			problems.append("%s does not reach a floor at the bottom (row %d)" % (name, bottom_row))
		top_row = int(top // CELL)
		beside = [level.at(top_row, c - 1), level.at(top_row, c + LADDER_COLS)]
		if not any(b in SOLIDS + ONE_WAYS for b in beside):
			problems.append("%s has no floor on either side at the top, where does it lead?" % name)
	# Presses: there has to be a ceiling above; the bottom lands on something solid or a one-way platform
	for name, x, y, ceiling, _ in level.presses:
		c, r = int(x // CELL), int(y // CELL)
		if ceiling <= 0 and not level.solid(-1, c):
			problems.append("%s has no ceiling above (what does it hang from?)" % name)
		if level.at(r + TRAP_ROWS, c) not in SOLIDS + ONE_WAYS:
			problems.append("%s has no floor below" % name)
	# Gates: directly above the gate it has to be solid all the way until it meets a whole ceiling (a row solid on both sides of the gate too) or the top of the view —
	# the gate is 64 tall and a jump 87, so any gap left would be jumped. Inside a factory it meets the ceiling; outdoors it has to be sealed all the way to the top
	for name, x, y, _ in level.gates + [(d[0], d[1], d[2], 0.0) for d in level.doors]:
		c, r = int(x // CELL), int(y // CELL)
		sealed = True
		for rr in range(r - 1, -1, -1):
			if not (level.solid(rr, c) and level.solid(rr, c + 1)):
				sealed = False
				break
			if level.solid(rr, c - 1) and level.solid(rr, c + 2):
				break
		if not sealed:
			problems.append("%s is not sealed above, it can be jumped over" % name)
		if not level.solid(r + TRAP_ROWS, c):
			problems.append("%s has no floor below" % name)
	for name, x, y in level.crates:
		c, r = int(x // CELL), int((y + CRATE_H) // CELL)
		if not (level.supports(r, c) or level.at(r, c) == "K"):
			problems.append("%s is floating, nothing below" % name)
	for name, x, y in level.barrels:
		c, r = int(x // CELL), int((y + BARREL_H / 2.0) // CELL)
		if not level.supports(r, c):
			problems.append("%s is floating, nothing below" % name)
	for name, x, y, _ in level.spikes:
		# Spikes are set into the floor surface: both cells below have to be solid (not on one-way platforms — people could come up through from below)
		c, r = int(x // CELL), int((y + 32 - SPIKE_SINK) // CELL)
		if not (level.solid(r, c) and level.solid(r, c + 1)):
			problems.append("%s does not have a solid floor below" % name)
	for label, kind, x, y in level.enemies:
		if kind not in chasers:
			continue
		c = int(x // CELL)
		if kind in level.hanging:
			# Those hanging only charge after landing: check the layer they drop onto
			r = next((rr for rr in range(level.height) if level.standable(rr, c)), None)
			if r is None:
				continue
		else:
			r = int((y + level.stand_of(kind)) // CELL)
		for step in (-1, 1):
			cc = c
			while level.standable(r, cc + step):
				cc += step
			beyond = cc + step
			if 0 <= beyond < level.width and level.is_pit(r, beyond):
				problems.append("%s (a charger): the path under it ends in a pit on the %s (column %d), it would fall in before reaching the player"
					% (label, "left" if step < 0 else "right", beyond))
	if min_enemies and level.vertical:
		# Vertical stages count in stretches of "one screen tall" (360 = 22.5 cells), from the bottom up; the spawn screen and the two boss screens do not count
		band = SCREEN_ROWS
		bottom = level.height * CELL
		screens = int(level.height // band)
		for screen in range(1, screens):
			hi = bottom - (screen + 1) * band * CELL
			lo = bottom - screen * band * CELL
			if level.boss_cell is not None and hi < (level.boss_cell[0] + 1) * CELL + 2 * band * CELL:
				continue
			count = sum(1 for e in level.enemies if hi <= e[3] < lo)
			if count < min_enemies:
				problems.append("Screen %d from the bottom has only %d enemies (at least %d)" % (screen + 1, count, min_enemies))
	elif min_enemies:
		screens = level.width // 40
		# The two boss area screens (the boss screen and the one before it) do not count: that is a one-on-one fight
		if level.boss_cell is not None:
			screens = min(screens, level.boss_cell[1] // 40 - 1)
		# The mid-boss room (between entrance door [ and exit door ]) is one-on-one too: screens that overlap it do not count
		entries = sorted(d[1] for d in level.doors if not d[3])
		exits = sorted(d[1] for d in level.doors if d[3])
		arenas = [(x0, min((x1 for x1 in exits if x1 > x0), default=x0)) for x0 in entries]
		for screen in range(1, screens):
			lo, hi = screen * 40 * CELL, (screen + 1) * 40 * CELL
			if any(x0 < hi and x1 > lo for x0, x1 in arenas):
				continue
			count = sum(1 for e in level.enemies if lo <= e[2] < hi)
			if count < min_enemies:
				problems.append("Screen %d has only %d enemies (at least %d)" % (screen + 1, count, min_enemies))
	# Enemies: none on the spawn screen (players would be shot as soon as they arrive); those standing need standable ground under their feet and their bodies not stuck in walls;
	# The column under a hanging one needs ground (it has to land somewhere when it drops); flyers must not be stuck in walls
	for label, kind, x, y in level.enemies:
		c = int(x // CELL)
		if level.vertical:
			# In vertical stages the "spawn screen" is the bottom screen; **nothing within `SAFE_RADIUS` of the spawn either** —
			# a gunner shooting diagonally down placed just out of view but in range would snipe players the moment they arrive (decided in the horizontal version of stage 4)
			if y > level.height * CELL - SCREEN_ROWS * CELL or \
					((x - level.spawn[0]) ** 2 + (y - level.spawn[1]) ** 2) ** 0.5 < SAFE_RADIUS:
				problems.append("%s is on the spawn screen / too close to the spawn" % label)
		elif x < safe_cols * CELL:
			problems.append("%s is on the spawn screen (column %d)" % (label, c))
		if kind in level.hanging:
			if not any(level.standable(r, c) for r in range(level.height)):
				problems.append("%s hangs over a column with no ground below, it would die from the fall" % label)
			continue
		if kind in level.floating:
			if level.solid(int(y // CELL), c):
				problems.append("%s is floating inside a wall" % label)
			continue
		r = int((y + level.stand_of(kind)) // CELL)
		if not level.standable(r, c):
			problems.append("%s stands at cell (%d, %d) with no surface underfoot or its body stuck in a wall" % (label, r, c))
	return problems


# ---------------------------------------------------------------- Picture: tiles (2026-10, the user asked for "as close to the promo art as possible, more structure and detail")
#
# Collision is still those platform nodes (hidden, not drawn, in stages generated from maps), and the picture is handed to `TileArt`:
# each cell draws a quarter of a 32×32 tile, which tile and which corner chosen by where the cell is in its solid area (top edge, side, corner, inside).
# Tile numbers are those of the industrial zone art `1 Tiles/IndustrialTile_NN.png` (`terrain_build.py` lays the 81 tiles out in one atlas).

## Each material's nine-slice: (top, middle, bottom) × (left, middle, right). The steel plate set was identified by its seams (4/5/6, 13/14/15, 22/23/24; 14 joins itself on all four sides).
NINE = {
	"#": ((4, 5, 6), (13, 14, 15), (22, 23, 24)),
	"%": ((58, 59, 60), (67, 68, 69), (67, 68, 69)),
	"~": ((74, 75, 76), (13, 14, 15), (22, 23, 24)),
	"-": ((74, 75, 76), (13, 14, 15), (22, 23, 24)),
	"=": ((77, 78, 79), (77, 78, 79), (77, 78, 79)),
	":": ((18, 18, 27), (18, 18, 27), (18, 18, 27)),
}
## Steel crate: one whole block is one crate, aligned to the 32-pixel grid, with each of the four corners taking one corner.
CRATES = (36, 62)
## The indoor background wall: mostly flat dark wall panels, with a few with panels / bars mixed in (picked at random per 32-pixel block, fixed seed).
BACK_TILES = [(21, 12), (3, 2), (47, 1)]
## The vertical red and white pipe (`!`): the topmost section has a cap (45), going down it alternates (54 / 63).
PIPE_TOP = 45
PIPE_BODY = (54, 63)
## Props scattered automatically on indoor floors (the industrial zone props), and roughly every how many cells one goes.
## No red `barrel`: it is the same image as **the exploding barrel**, and a pile that does not explode would leave players unable to tell them apart (seen in a 2026-10 screenshot).
## No `locker` / `board` either: those two hang on walls, the bottom of the art is 7~9 pixels above the bottom of the canvas, and on the floor they float — to use them, hang them on a wall by name in the map.
INDOOR_PROPS = ["box", "extinguisher", "bucket", "box_open", "barrel_rust", "crate"]
PROP_STEP = (5, 11)
## Scattered on open ground too (2026-10, the user: "avoid large empty scenes as much as possible"), with a set of things that belong outdoors
OUTDOOR_PROPS = ["barrel_rust", "box", "warning", "bucket", "crate", "box_open", "bench"]
## How many tiles per atlas row (9 for industrial, 12 for green), and how much the background wall is darkened.
COLUMNS = 9
BACK_TINT = (0.72, 0.72, 0.8)
## Only cells with something solid within this many cells overhead count as "indoors" (None = search all the way up). In a shaft every cell has something overhead sooner or later,
## and searching all the way up would put walls along the whole shaft, hiding every bit of the parallax background behind it.
INDOOR_REACH = None
## Props are scattered on one-way platforms too (only on in the shaft zone)
PROPS_ON_LEDGES = False

## **One tile set per zone** (split out while making stage 1 in 2026-10): the constants above are the industrial set, and `use_theme()` swaps in another zone's.
## The green zone (stage 1, `green-zone-tileset/Tileset.png`, 12 columns, number = row × 12 + column + 1) was **identified by the black outlines on the four edges**:
## turf blocks 1/2/3, 13/14/16, 25/26/28; stone brick top 9/10/12, the stone brick body is the dark brick-patterned 53/54/41, bottom 67/27/68;
## single-row turf ledges (soil hanging below) 49/50/51, single-row stone ledges 44/45/46; a whole stone 30; one-cell-wide turf pillars 5/17/29.
## The dark purple fill + sparse brick pattern (54, 55, 37~40) is **the cave wall** — the green zone's "indoors" is underground caves.
THEMES = {
	"industrial": {
		"NINE": dict(NINE), "CRATES": CRATES, "BACK_TILES": BACK_TILES, "PIPE_TOP": PIPE_TOP,
		"PIPE_BODY": PIPE_BODY, "INDOOR_PROPS": INDOOR_PROPS, "OUTDOOR_PROPS": OUTDOOR_PROPS,
		"COLUMNS": 9, "BACK_TINT": (0.72, 0.72, 0.8),
	},
	"green": {
		"NINE": {
			"#": ((1, 2, 3), (13, 14, 16), (25, 26, 28)),
			"%": ((9, 10, 12), (53, 54, 41), (67, 27, 68)),
			"~": ((9, 10, 12), (53, 54, 41), (67, 27, 68)),
			"-": ((9, 10, 12), (53, 54, 41), (67, 27, 68)),
			"=": ((49, 50, 51), (49, 50, 51), (49, 50, 51)),
			":": ((44, 45, 46), (44, 45, 46), (44, 45, 46)),
		},
		"CRATES": (30,),
		# Mostly flat dark blocks (19 / 20), with a few mossy ones (54 / 55) mixed in: the mossy one repeated cell after cell is too loud (seen in a screenshot)
		"BACK_TILES": [(19, 8), (20, 6), (54, 2), (55, 1)],
		# `!` in the green zone is a turf stone pillar in the background (the one-cell-wide set: grassy top + body)
		"PIPE_TOP": 5, "PIPE_BODY": (17, 17),
		# No `box`: the green zone's breakable crate is this very image (`cyberpunk_trap_crate.tscn`), and a pile of unbreakable ones would confuse people
		"INDOOR_PROPS": ["rock_small", "rock", "bin", "rock_small", "grass_tuft"],
		"OUTDOOR_PROPS": ["grass_tuft", "grass_blade", "bush_flat", "rock_small", "grass_tuft", "bush_big",
			"bench", "rock", "grass_blade", "bin"],
		"COLUMNS": 12, "BACK_TINT": (0.8, 0.8, 0.86),
	},
	## Bar street (stage 3, `bar-street-tileset/1 Tiles/Tiles_01..100`, 10 columns):
	## ground and floors = brown brick with a wooden beam top (1/2/4, 11/12/14, 21/22/24, identified by the black outlines); the single-row beam bricks 31/32/34 are the one-way floors (`:`);
	## ledges = blue striped awnings 7/8/9 (as in the horizontal version: jumping on the shops' awnings in the street);
	## blocking walls = pulled-down blue shutters (top 29/28/30, body 39/38/40) — a "shutter" itself says no way through;
	## the whole brown brick 44 is cover; **indoors** (in buildings) is the grey brick wall 60 with a few cracked 70/80/90 mixed in; `!` is the grey drainpipe 79/89.
	"bar": {
		"NINE": {
			"#": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"%": ((29, 28, 30), (39, 38, 40), (39, 38, 40)),
			"~": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"-": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"=": ((7, 8, 9), (7, 8, 9), (7, 8, 9)),
			":": ((31, 32, 34), (31, 32, 34), (31, 32, 34)),
		},
		"CRATES": (44,),
		"BACK_TILES": [(60, 12), (70, 2), (80, 1), (90, 1)],
		"PIPE_TOP": 79, "PIPE_BODY": (89, 89),
		# No bottles, glasses, flying banknotes or swinging signs (they look like pickups, see CLAUDE.md); `bin` (actually a cow skull) and `crate`
		# (a knife lying flat) are not scattered either — small things filling the floor look like a floor full of pickups in screenshots
		"INDOOR_PROPS": ["stool", "keg", "stool2", "keg"],
		# Neon signs (`sign` / `sign2`) hang on walls and are not scattered on the floor — to use them, hang them high by name in the map
		"OUTDOOR_PROPS": ["keg"],
		"COLUMNS": 10, "BACK_TINT": (0.75, 0.75, 0.8),
	},
	## Basement (stage 4, vertical, `basement-tileset/1 Tiles/Tile_01..70`, 10 columns):
	## rock nine-slice 1/2/4, 11/12/14, 21/22/24 (dark purple fill + light blue outline); ledges 41/42/44 (only the top half drawn);
	## one-brick-thick strips 31/32/34 are the second kind of one-way ledge; the whole stone 35 / the frame with a light 37 are cover;
	## **indoors** is the brick wall 67 (mostly) / 68 / 70 / 69 (cracks, broken bricks), darkened much more — it is behind the shaft; `!` is the vertical pipe 65.
	## In a shaft every cell has something overhead sooner or later, so walls only go where there is something solid **within 10 cells overhead** (`INDOOR_REACH`),
	## and elsewhere the parallax basement wall behind shows through.
	"basement": {
		"NINE": {
			"#": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"%": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"~": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"-": ((1, 2, 4), (11, 12, 14), (21, 22, 24)),
			"=": ((41, 42, 44), (41, 42, 44), (41, 42, 44)),
			":": ((31, 32, 34), (31, 32, 34), (31, 32, 34)),
		},
		"CRATES": (35, 37),
		"BACK_TILES": [(67, 70), (68, 18), (70, 8), (69, 4)],
		"PIPE_TOP": 65, "PIPE_BODY": (65, 65),
		"INDOOR_PROPS": ["box", "box_moss", "box_small", "pipe", "pipe_moss", "grass", "fan", "unit", "pipe_bend"],
		"OUTDOOR_PROPS": ["box", "box_small", "pipe", "grass", "grass2", "fan", "unit", "container", "pipe_moss"],
		"COLUMNS": 10, "BACK_TINT": (0.55, 0.55, 0.62),
		"INDOOR_REACH": 10, "PROPS_ON_LEDGES": True,
	},
	## Lab (stage 5, `lab-tileset/1 Tiles/Tiles_01..100`, 10 columns):
	## floors and ground = teal diagonal-ridged steel plate 1/2/3, 11/12/13, 21/22/23; walls and blocks (`%`) = clean grey-blue wall panels 7/8/9, 17/18/19, 27/28/29;
	## ledges = one-brick-thick ridged strips 51/52/53, the second kind of one-way ledge = grey-blue strips 57/58/59;
	## **cover uses the two with windows (32 / 38), not the X-braced 31 / 37**: the breakable crate is cut from 31, and a pile of unbreakable ones would confuse people;
	## **indoors** is the dark background tiles in column 10 (mostly plain 30 / 40, with a few speckled 20 and ridged 10).
	"lab": {
		"NINE": {
			"#": ((1, 2, 3), (11, 12, 13), (21, 22, 23)),
			"%": ((7, 8, 9), (17, 18, 19), (27, 28, 29)),
			"~": ((1, 2, 3), (11, 12, 13), (21, 22, 23)),
			"-": ((1, 2, 3), (11, 12, 13), (21, 22, 23)),
			"=": ((51, 52, 53), (51, 52, 53), (51, 52, 53)),
			":": ((57, 58, 59), (57, 58, 59), (57, 58, 59)),
		},
		"CRATES": (32, 38),
		"BACK_TILES": [(30, 12), (40, 6), (20, 2), (10, 1)],
		"PIPE_TOP": 30, "PIPE_BODY": (30, 30),
		# Incubators, desks and chairs, small monitors; the animated ones (generators, valves, scanners, cameras) are placed by name in the map
		# Intact canisters are always breakable gas capsules (`K`); the props only use the fully shattered image
		"INDOOR_PROPS": ["chair", "table", "monitor3", "chair2", "table2", "capsule_shards"],
		"OUTDOOR_PROPS": ["capsule_shards", "grass", "grass2", "table", "chair"],
		"COLUMNS": 10, "BACK_TINT": (0.7, 0.72, 0.8),
		# The breakable things are **gas capsules**: 48 tall, one per three rows of `K`, two stacked per six rows (96, too high to jump)
		"CRATE_H": 48, "CRATE_SCENE": "res://scenes/trap_capsule.tscn",
	},
}


def use_theme(name):
	"""Switch to a zone's tile set and props (the module's constants are swapped directly, and the code after reads them as usual)."""
	global NINE, CRATES, BACK_TILES, PIPE_TOP, PIPE_BODY, INDOOR_PROPS, OUTDOOR_PROPS, COLUMNS, BACK_TINT
	global INDOOR_REACH, PROPS_ON_LEDGES, CRATE_H, CRATE_SCENE
	t = THEMES[name]
	NINE, CRATES, BACK_TILES = t["NINE"], t["CRATES"], t["BACK_TILES"]
	PIPE_TOP, PIPE_BODY = t["PIPE_TOP"], t["PIPE_BODY"]
	INDOOR_PROPS, OUTDOOR_PROPS = t["INDOOR_PROPS"], t["OUTDOOR_PROPS"]
	COLUMNS, BACK_TINT = t["COLUMNS"], t["BACK_TINT"]
	INDOOR_REACH = t.get("INDOOR_REACH")
	PROPS_ON_LEDGES = t.get("PROPS_ON_LEDGES", False)
	CRATE_H = t.get("CRATE_H", 24)
	CRATE_SCENE = t.get("CRATE_SCENE", "res://scenes/trap_crate.tscn")


def _hash(a, b, seed):
	return ((a * 73856093) ^ (b * 19349663) ^ seed) & 0x7FFFFFFF


def tile_cells(level, seed=20261003):
	"""Work out which corner of which tile each cell of the foreground (solid, one-way) and background (indoor walls) draws. Returns two flat integer tables (foreground, background)."""
	front, back = [], []
	for r in range(level.height):
		for c in range(level.width):
			ch = level.at(r, c)
			if ch in SOLIDS or ch in ONE_WAYS:
				tile, quarter = _front_tile(level, r, c, ch, seed)
				front += [c, r, tile, quarter]
			elif ch == "!":
				left = c if level.at(r, c - 1) != "!" else c - 1
				top = r
				while level.at(top - 1, c) == "!":
					top -= 1
				block = (r - top) // 2
				tile = PIPE_TOP if block == 0 else PIPE_BODY[block % 2]
				back += [c, r, tile, (c - left) % 2 + 2 * ((r - top) % 2)]
			elif _indoor(level, r, c):
				total = sum(w for _, w in BACK_TILES)
				pick = _hash(c // 2, r // 2, seed) % total
				for tile, w in BACK_TILES:
					if pick < w:
						break
					pick -= w
				back += [c, r, tile, (c % 2) + 2 * (r % 2)]
	return front, back


def _front_tile(level, r, c, ch, seed):
	if ch == "X":
		crate = CRATES[_hash(c // 2, r // 2, seed) % len(CRATES)]
		return crate, (c % 2) + 2 * (r % 2)
	same = lambda rr, cc: level.at(rr, cc) == ch
	left, right = not same(r, c - 1), not same(r, c + 1)
	top, bottom = not same(r - 1, c), not same(r + 1, c)
	row = 0 if top else (2 if bottom else 1)
	col = 0 if left and not right else (2 if right and not left else (0 if left else 1))
	tile = NINE[ch][row][col]
	qx = 0 if left else (1 if right else c % 2)
	qy = 0 if top else (1 if bottom else r % 2)
	return tile, qx + 2 * qy


def _indoor(level, r, c):
	"""Is there a **solid** floor / ceiling above this cell (up the same column) — if so it is indoors and gets the background wall.
	One-way platforms do not count: under an open-air girder walkway it is still open air (the first version counted them, and dark wall patches under the walkways were obvious at a glance in screenshots)."""
	top = -1 if INDOOR_REACH is None else max(-1, r - 1 - INDOOR_REACH)
	for rr in range(r - 1, top, -1):
		if level.solid(rr, c):
			return True
	return False


# ---------------------------------------------------------------- Decals: pipes, number signs (on walls); railings (on floors)
#
# That group of purple geometric tiles in the art is **a pipe network** (identified by which stretches of the four edges are purple):
# 20 horizontal pipe, 1 vertical pipe, 38 / 30 left / right end of a horizontal pipe, 10 / 28 top / bottom end of a vertical pipe, 39 a joint with a big disc (joining thick pipes on all four sides).
# The big purple pipe on the promo art's wall is "pipe end → horizontal pipe → disc → …" joined up; a digit (`3 Objects/0~9.png`) laid on a disc is a number sign.
# Pipes take corners in **32-pixel block** coordinates (a block = 2×2 cells), horizontal and vertical only; drawn on top of the indoor wall layer (pipe tiles have their own dark backing).
PIPE_BY_DIRS = {
	frozenset("EW"): 20, frozenset("NS"): 1,
	frozenset("E"): 38, frozenset("W"): 30, frozenset("S"): 10, frozenset("N"): 28,
}
PIPE_JOINT = 39


def pipe_blocks(pipes, signs):
	"""Spread each pipe (a list of corners in block coordinates) into "which directions this block connects", returning {block: tile number}.
	Corners, branches and number sign blocks all draw the disc joint."""
	dirs = {}
	for path in pipes:
		for (x0, y0), (x1, y1) in zip(path, path[1:]):
			if x0 != x1 and y0 != y1:
				raise SystemExit("Pipes can only run horizontally or vertically: %s -> %s" % ((x0, y0), (x1, y1)))
			dx = (x1 > x0) - (x1 < x0)
			dy = (y1 > y0) - (y1 < y0)
			x, y = x0, y0
			while (x, y) != (x1, y1):
				nx, ny = x + dx, y + dy
				dirs.setdefault((x, y), set()).add("E" if dx > 0 else "W" if dx < 0 else "S" if dy > 0 else "N")
				dirs.setdefault((nx, ny), set()).add("W" if dx > 0 else "E" if dx < 0 else "N" if dy > 0 else "S")
				x, y = nx, ny
	out = {}
	for block, d in dirs.items():
		out[block] = PIPE_BY_DIRS.get(frozenset(d), PIPE_JOINT)
	for _, bx, by in signs:
		out[(bx, by)] = PIPE_JOINT
	return out


def decor_cells(pipes, signs):
	"""The tiles of pipes and number signs (a quarter per cell, the same format as `TileArt`)."""
	cells = []
	for (bx, by), tile in sorted(pipe_blocks(pipes, signs).items()):
		for q in range(4):
			cells += [bx * 2 + q % 2, by * 2 + q // 2, tile, q]
	return cells


def rail_props(rails):
	"""Railings: (from column, to column, standing on row). Left end, middle and right end are 32 wide each, put together in 2-cell sections."""
	out = []
	for c0, c1, row in rails:
		cols = list(range(c0, c1 + 1, 2))
		for i, c in enumerate(cols):
			prop = "fence" if i == 0 else ("fence_end" if i == len(cols) - 1 else "fence_mid")
			out.append((prop, c, row))
	return out


def dress(level, named, seed=20261003):
	"""Props: first place the ones named in the map (`named`: (prop name, column, standing on row)), then scatter automatically on floors (one set indoors, one outdoors).
	When scattering, avoid the cells of ladders, traps and enemies, and keep props at least a few cells apart."""
	# Whole building fronts (bar street's `facade_N`) go first and are drawn furthest back: otherwise a building would cover the bars and signs placed before it
	named = sorted(named, key=lambda p: not p[0].startswith("facade"))
	for prop, c, r in named:
		level.props.append(("Prop%d" % (len(level.props) + 1), prop, c * CELL, r * CELL))
	busy = set()
	for name, x, top, height in level.ladders:
		lc = int((x - CELL) // CELL)
		for cc in range(lc - 1, lc + 3):
			busy.add(cc)
	for _, x, _, _, _ in level.presses:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 3))
	for _, x, _, _ in level.gates + level.doors:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 3))
	for _, x, _ in level.crates:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 3))
	for _, x, _ in level.barrels:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 2))
	for _, x, _, _ in level.spikes:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 3))
	taken = {(int(p[2] // CELL), int(p[3] // CELL)) for p in level.props}
	enemy_cells = {(int(x // CELL), int((y + 16) // CELL)) for _, _, x, y in level.enemies}
	state = [seed]

	def roll(n):
		state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
		return state[0] % max(1, n)

	for r in range(level.height):
		c = 0
		next_at = roll(PROP_STEP[1])
		while c < level.width:
			# Not scattered on steel crates / stones (X): those are blocks of cover, and a bench on top looks like a stack of acrobats
			# The shaft (stage 4) is mostly one-way platforms, and scattering only on solid floors would leave a few dozen props in the whole shaft — that zone scatters on platforms too
			ground = level.solid(r, c) or (PROPS_ON_LEDGES and level.at(r, c) in ONE_WAYS)
			floor = ground and not level.solid(r - 1, c) and level.body_free(r, c) \
				and level.at(r, c) != "X"
			if floor and c >= next_at and c not in busy and (c, r) not in taken \
					and not any((cc, r) in enemy_cells for cc in range(c - 2, c + 3)):
				pool = INDOOR_PROPS if _indoor(level, r - 1, c) else OUTDOOR_PROPS
				prop = pool[roll(len(pool))]
				level.props.append(("Prop%d" % (len(level.props) + 1), prop, c * CELL, r * CELL))
				next_at = c + PROP_STEP[0] + roll(PROP_STEP[1] - PROP_STEP[0])
			c += 1


# ---------------------------------------------------------------- Writing scenes

def build(level, out, root, prop_dir, write, prop_frames=None, named_props=(), decor=None):
	decor = decor or {}
	named_props = list(named_props) + rail_props(decor.get("rails", []))
	ids = {}
	extra = []
	for index, kind in enumerate(sorted({e[1] for e in level.enemies})):
		ids[kind] = "e%d" % index
		extra.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (level.enemy_scenes[kind], ids[kind]))
	extra.append('[ext_resource type="PackedScene" path="res://scenes/ladder.tscn" id="t2"]')
	front, back = tile_cells(level)
	back += decor_cells(decor.get("pipes", []), decor.get("signs", []))
	dress(level, named_props)
	signs = decor.get("signs", [])
	extra.append('[ext_resource type="Script" path="res://scripts/tile_art.gd" id="ta"]')
	extra.append('[ext_resource type="Script" path="res://scripts/prop.gd" id="21"]')
	# Textures (the tile atlas, props) are **written as paths, not as ext_resource**: they are third-party art, absent from the public version,
	# and referencing a missing file stops the whole scene from loading; written as paths, a missing one is simply not drawn (`TileArt` / `Prop` load them themselves).
	atlas_line = 'atlas_path = "res://skins/%s/tiles/atlas.png"\n' % prop_dir

	def prop_path(prop):
		return "res://skins/%s/props/%s.png" % (prop_dir, prop)
	if level.presses:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t0"]' % lb.PRESS_SCENE)
	if level.gates:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t1"]' % lb.GATE_SCENE)
	if level.belts:
		extra.append('[ext_resource type="Script" path="res://scripts/belt_art.gd" id="bl"]')
	if level.crates:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t3"]' % CRATE_SCENE)
	if level.barrels:
		extra.append('[ext_resource type="PackedScene" path="res://scenes/trap_barrel.tscn" id="t4"]')
	if level.spikes:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t5"]' % SPIKE_SCENE)
	if level.doors:
		extra.append('[ext_resource type="PackedScene" path="res://scenes/arena_door.tscn" id="t6"]')
	width = level.width * CELL
	# Tiles per atlas row: the industrial zone uses TileArt's default 9 and does not write it; other zones write it
	columns_line = "" if COLUMNS == 9 else "columns = %d\n" % COLUMNS
	lines = [lb.HEAD + "\n".join(extra) + "\n"]
	lines.append('\n[node name="%s" type="Node2D"]\nscript = ExtResource("3")\n' % root)
	if level.vertical:
		# Vertical stages: the fall-out line is 40 below the very bottom (once the view scrolls up, main.gd measures from the bottom of the view)
		lines.append("fall_y = %g\n" % (level.height * CELL + 40.0))
	# Draw order: background (the parallax layers, inserted at the front when the stage loads) → indoor walls → props → solid tiles → platforms (hidden) → traps → enemies
	lines.append('\n[node name="BackTiles" type="Node2D" parent="."]\nscript = ExtResource("ta")\n' +
		atlas_line + '%stint = Color(%g, %g, %g, 1)\ncells = PackedInt32Array(%s)\n'
		% ((columns_line,) + tuple(BACK_TINT) + (", ".join(str(v) for v in back),)))
	# The digits on number signs: laid in the middle of the disc, drawn on top of the wall layer
	lines.append('\n[node name="Decals" type="Node2D" parent="."]\n')
	for i, (digit, bx, by) in enumerate(signs):
		lines.append('\n[node name="Sign%d" type="Sprite2D" parent="Decals"]\nscript = ExtResource("21")\n'
			'texture_path = "%s"\nbottom_left = false\nposition = Vector2(%g, %g)\n'
			% (i + 1, prop_path("digit_%d" % digit), bx * 32 + 16, by * 32 + 16))
	lines.append('\n[node name="Props" type="Node2D" parent="."]\n')
	for name, prop, x, bottom in level.props:
		lines.append('\n[node name="%s" type="Sprite2D" parent="Props"]\n'
			'script = ExtResource("21")\ntexture_path = "%s"\nposition = Vector2(%g, %g)\n'
			% (name, prop_path(prop), x, bottom))
		if prop_frames and prop_frames.get(prop, 1) > 1:
			lines.append("frames = %d\n" % prop_frames[prop])
	lines.append('\n[node name="FrontTiles" type="Node2D" parent="."]\nscript = ExtResource("ta")\n' +
		atlas_line + '%scells = PackedInt32Array(%s)\n' % (columns_line, ", ".join(str(v) for v in front)))
	# The teeth of the middle section of a conveyor roll the way it carries (`BeltArt`), laid on top of the tiles
	if level.belts:
		lines.append('\n[node name="Belts" type="Node2D" parent="."]\nscript = ExtResource("bl")\n' +
			atlas_line + 'belts = PackedFloat32Array(%s)\n'
			% ", ".join("%g, %g, %g, %g" % (x, y, w, speed) for _, x, y, w, _, speed in level.belts))
	lines.append('\n[node name="Level" type="Node2D" parent="."]\n')
	for name, x, y, w, h in level.solids:
		# The picture is handled by tiles (`TileArt`), platforms only do collision, so they are hidden
		lines.append("\n" + lb.platform(name, "Level", x, y, w, h) + "visible = false\n")
	for name, x, y, w, h, speed in level.belts:
		lines.append("\n" + lb.platform(name, "Level", x, y, w, h) + "visible = false\nconveyor = %g\n" % speed)
	height = level.height * CELL if level.vertical else lb.SCREEN_H
	lines.append("\n" + lb.platform("WallLeft", "Level", -16, 0, 16, height))
	lines.append("\n" + lb.platform("WallRight", "Level", width, 0, 16, height))
	for name, x, y, w in level.ledges:
		lines.append("\n" + lb.platform(name, "Level", x, y, w, 16, one_way=True) + "visible = false\n")
	for name, x, top, height in level.ladders:
		lines.append('\n[node name="%s" parent="Level" instance=ExtResource("t2")]\n'
			'position = Vector2(%g, %g)\nheight = %g\n' % (name, x, top, height))
	lines.append('\n[node name="Walls" type="Node2D" parent="Level"]\n')
	if level.presses or level.gates or level.crates or level.barrels or level.spikes or level.doors:
		lines.append('\n[node name="Traps" type="Node2D" parent="."]\n')
		for name, x, y, phase in level.spikes:
			lines.append('\n[node name="%s" parent="Traps" instance=ExtResource("t5")]\n'
				'position = Vector2(%g, %g)\nphase = %g\n' % (name, x, y, phase))
		for name, x, y in level.crates:
			lines.append('\n[node name="%s" parent="Traps" instance=ExtResource("t3")]\n'
				'position = Vector2(%g, %g)\n' % (name, x, y))
		for name, x, y in level.barrels:
			lines.append('\n[node name="%s" parent="Traps" instance=ExtResource("t4")]\n'
				'position = Vector2(%g, %g)\n' % (name, x, y))
		for name, x, y, ceiling, phase in level.presses:
			lines.append('\n[node name="%s" parent="Traps" instance=ExtResource("t0")]\n'
				'position = Vector2(%g, %g)\nphase = %g\nmount_y = %g\n' % (name, x, y, phase, ceiling))
		for name, x, y, phase in level.gates:
			lines.append('\n[node name="%s" parent="Traps" instance=ExtResource("t1")]\n'
				'position = Vector2(%g, %g)\nphase = %g\n' % (name, x, y, phase))
		for name, x, y, is_exit in level.doors:
			lines.append('\n[node name="%s" parent="Traps" instance=ExtResource("t6")]\n'
				'position = Vector2(%g, %g)\n%s' % (name, x, y, "exit_door = true\n" if is_exit else ""))
	lines.append('\n[node name="Enemies" type="Node2D" parent="."]\n')
	for name, kind, x, y in level.enemies:
		lines.append('\n[node name="%s" parent="Enemies" instance=ExtResource("%s")]\n'
			'position = Vector2(%g, %g)\n' % (name, ids[kind], x, y))
	lines.append('\n[node name="Fx" type="Node2D" parent="."]\n'
		'script = ExtResource("13")\n'
		'muzzle_flash_scene = ExtResource("14")\n'
		'hit_spark_scene = ExtResource("15")\n'
		'impact_spark_scene = ExtResource("16")\n'
		'explosion_scene = ExtResource("18")\n')
	lines.append('\n[node name="Player" parent="." instance=ExtResource("2")]\n'
		'position = Vector2(%g, %g)\n' % level.spawn)
	lines.append('\n[node name="Camera2D" type="Camera2D" parent="."]\n'
		'position = Vector2(%g, %g)\n'
		'script = ExtResource("17")\n%s'
		'limit_left = 0\nlimit_top = 0\nlimit_right = %d\nlimit_bottom = %d\n'
		% (level.spawn[0], level.spawn[1], "only_up = true\n" if level.vertical else "", width,
			level.height * CELL if level.vertical else lb.SCREEN_H))
	lines.append('\n[node name="HUD" parent="." instance=ExtResource("6")]\n')
	lines.append('\n[node name="PauseMenu" parent="." instance=ExtResource("19")]\n')
	lines.append('\n[node name="DeathScreen" parent="." instance=ExtResource("20")]\n')
	lines.append('\n[node name="ClearScreen" parent="." instance=ExtResource("22")]\n')
	text = "".join(lines)
	if write:
		with open(out, "w", newline="\n", encoding="utf-8") as f:
			f.write(text)
	return text
