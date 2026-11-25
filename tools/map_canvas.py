"""A small tool for drawing grid maps: describes a segment of map by "drawing rectangles", much less error-prone than hand-typing dozens of columns of characters.

    cv = Canvas(80)                 # 80 cells wide (a screen is 40 cells)
    cv.ground(0, 79)                # ground (rows 20~22), the material can change: cv.ground(30, 40, "%")
    cv.floor(10, 30, 13)            # a floor on row 13 (columns 10~30)
    cv.fill(40, 41, 8, 15)          # a solid block: columns 40~41, rows 8~15
    cv.ladder(38, 7, 20)            # ladder: columns 38~39, from row 7 (the floor at the ladder top) to row 20 (the floor below)
    cv.put(22, 9, "P")              # press / gate / enemy letter / @ / > / B
    cv.prop("locker", 50, 20)       # a prop placed by name: standing on row 20
    cv.pipe([(21, 4), (39, 4)])     # a pipe on the wall (coordinates in 32-pixel blocks), cv.sign(2, 30, 4) number sign, cv.rail(62, 76, 7) railing
    cv.rows()                       # → 23 row strings, handed to map_build.MapLevel

All coordinates are **this segment's own**; when joined into a whole stage `stitch()` shifts them right.
What the rows mean is in `map_build.py`: the floors of the usual three layers are on rows 7 / 13 / 20.
"""

import map_build as mb


class Canvas:
	def __init__(self, width, height=None):
		if width % 2:
			raise SystemExit("A segment must be an even number of cells wide (pipes align to 2-cell blocks): %d" % width)
		self.width = width
		## A segment of a horizontal stage is one screen tall (23 rows); a segment of a vertical stage can be taller (stage 4 segments are 45 rows = two screens)
		self.height = height or mb.ROWS
		self.grid = [["."] * width for _ in range(self.height)]
		self.props = []
		self.pipes = []
		self.signs = []
		self.rails = []

	def fill(self, c0, c1, r0, r1, ch="#"):
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				if 0 <= r < self.height and 0 <= c < self.width:
					self.grid[r][c] = ch

	def ground(self, c0, c1, ch="#"):
		self.fill(c0, c1, self.height - 3, self.height - 1, ch)

	def floor(self, c0, c1, row, ch="#"):
		self.fill(c0, c1, row, row, ch)

	def clear(self, c0, c1, r0, r1):
		self.fill(c0, c1, r0, r1, ".")

	def ladder(self, c, top, bottom):
		"""The top of the ladder on row top (that floor gets a hole), the bottom landing on the floor of row bottom."""
		self.fill(c, c + 1, top, bottom - 1, "H")

	def put(self, c, r, ch):
		self.grid[r][c] = ch

	## How many rows stacking some crates takes (one is 24 tall, a cell 16): see `map_build.CRATE_H`
	CRATE_ROWS = {1: 2, 2: 3, 3: 5, 4: 6}

	def crates(self, c, row, count=1):
		"""Breakable crates: columns c~c+1, standing on the floor of row row, count stacked."""
		rows = self.CRATE_ROWS[count]
		self.fill(c, c + 1, row - rows, row - 1, "K")

	def barrel(self, c, row):
		"""Barrel: standing on the floor of row row."""
		self.put(c, row - 1, "O")

	def belt(self, c0, c1, row, direction):
		"""Conveyor: one solid row, `direction` is 1 (right) or -1 (left)."""
		self.floor(c0, c1, row, "~" if direction > 0 else "-")

	def prop(self, name, c, row):
		self.props.append((name, c, row))

	def pipe(self, points):
		self.pipes.append(list(points))

	def sign(self, digit, bx, by):
		self.signs.append((digit, bx, by))

	def rail(self, c0, c1, row):
		self.rails.append((c0, c1, row))

	def rows(self):
		return ["".join(r) for r in self.grid]


def stitch(segments):
	"""Join segments into a whole stage: cells are joined sideways, and the coordinates of props, pipes, number signs and railings are shifted right."""
	rows = [""] * mb.ROWS
	props, pipes, signs, rails = [], [], [], []
	offset = 0
	for cv in segments:
		for r, line in enumerate(cv.rows()):
			rows[r] += line
		props += [(n, c + offset, row) for n, c, row in cv.props]
		pipes += [[(x + offset // 2, y) for x, y in path] for path in cv.pipes]
		signs += [(d, x + offset // 2, y) for d, x, y in cv.signs]
		rails += [(c0 + offset, c1 + offset, row) for c0, c1, row in cv.rails]
		offset += cv.width
	return rows, props, {"pipes": pipes, "signs": signs, "rails": rails}


def dump(rows, start=0, end=None):
	"""Print as a character picture (with a column ruler), for people to read and compare with the pixel image."""
	end = end or len(rows[0])
	ruler = "".join(str((c // 10) % 10) if c % 10 == 0 else " " for c in range(start, end))
	print("     " + ruler)
	for r, line in enumerate(rows):
		print("%3d  %s" % (r, line[start:end]))


def from_png(path):
	"""A pixel image the user painted by colour → one segment `Canvas` (the palette is in `map_paint.py`). The path can be relative to the repo root too.
	The image only has cells; props placed by name, pipes, number signs and railings are added separately on the returned `Canvas`."""
	import os
	import map_paint
	if not os.path.isabs(path):
		path = os.path.join(map_paint.ROOT, path)
	rows = map_paint.png_to_rows(path)
	cv = Canvas(len(rows[0]), len(rows))
	cv.grid = [list(r) for r in rows]
	return cv


def vstitch(segments):
	"""Vertical stages: segments are stacked **from the bottom up** (`segments[0]` is the bottom segment).
	Cells are joined vertically and the rows of props and railings are shifted down; wall pipes and number signs align to 32-pixel blocks and are not used in vertical stages."""
	order = list(reversed(segments))
	rows, props, rails = [], [], []
	offset = 0
	for cv in order:
		if cv.pipes or cv.signs:
			raise SystemExit("Segments of vertical stages do not draw pipes or number signs (a segment's height is not always even, so 32-pixel blocks do not line up)")
		rows += cv.rows()
		props += [(n, c, row + offset) for n, c, row in cv.props]
		rails += [(c0, c1, row + offset) for c0, c1, row in cv.rails]
		offset += cv.height
	return rows, props, {"pipes": [], "signs": [], "rails": rails}
