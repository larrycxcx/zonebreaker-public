"""画格子地图的小工具：按「画矩形」的方式描述一段地图，比手打几十列的字符画不容易错格。

    cv = Canvas(80)                 # 80 格宽（一屏 40 格）
    cv.ground(0, 79)                # 地面（第 20~22 行），可以换材质：cv.ground(30, 40, "%")
    cv.floor(10, 30, 13)            # 第 13 行一层楼板（第 10~30 列）
    cv.fill(40, 41, 8, 15)          # 实心块：第 40~41 列、第 8~15 行
    cv.ladder(38, 7, 20)            # 梯子：第 38~39 列，从第 7 行（梯子顶那层地板）通到第 20 行（底下那层地板）
    cv.put(22, 9, "P")              # 液压机 / 闸门 / 敌人字母 / @ / > / B
    cv.prop("locker", 50, 20)       # 点名摆的装饰：站在第 20 行上
    cv.pipe([(21, 4), (39, 4)])     # 墙上的管道（32 像素一块的坐标），cv.sign(2, 30, 4) 编号牌，cv.rail(62, 76, 7) 栏杆
    cv.rows()                       # → 23 行字符串，交给 map_build.MapLevel

坐标全是**这一段自己的**；拼成一整关时由 `stitch()` 统一往右挪。
行号的含义见 `map_build.py`：常用三层的地板在第 7 / 13 / 20 行。
"""

import map_build as mb


class Canvas:
	def __init__(self, width, height=None):
		if width % 2:
			raise SystemExit("一段要偶数格宽（管道按 2 格一块对齐）：%d" % width)
		self.width = width
		## 横向关一段就是一屏高（23 行）；纵向关的一段可以更高（第四关一段 45 行 = 两屏）
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
		"""梯子顶在第 top 行（那层地板留洞），底落在第 bottom 行的地板上。"""
		self.fill(c, c + 1, top, bottom - 1, "H")

	def put(self, c, r, ch):
		self.grid[r][c] = ch

	## 摞几只箱子要占几行（一只 24 高、一格 16）：见 `map_build.CRATE_H`
	CRATE_ROWS = {1: 2, 2: 3, 3: 5, 4: 6}

	def crates(self, c, row, count=1):
		"""可打爆的箱子：第 c~c+1 列，站在第 row 行的地板上，摞 count 只。"""
		rows = self.CRATE_ROWS[count]
		self.fill(c, c + 1, row - rows, row - 1, "K")

	def barrel(self, c, row):
		"""油桶：站在第 row 行的地板上。"""
		self.put(c, row - 1, "O")

	def belt(self, c0, c1, row, direction):
		"""传送带：一行实心，`direction` 是 1（往右）或 -1（往左）。"""
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
	"""把一段段拼成一整关：格子横着接起来，装饰、管道、编号牌、栏杆的坐标往右挪。"""
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
	"""打印成字符画（带列号刻度），给人看、和像素图对照用。"""
	end = end or len(rows[0])
	ruler = "".join(str((c // 10) % 10) if c % 10 == 0 else " " for c in range(start, end))
	print("     " + ruler)
	for r, line in enumerate(rows):
		print("%3d  %s" % (r, line[start:end]))


def from_png(path):
	"""用户按颜色画的一张像素图 → 一段 `Canvas`（颜色表见 `map_paint.py`）。路径相对仓库根目录也行。
	图里只有格子；点名摆的装饰、管道、编号牌、栏杆在拿到的 `Canvas` 上另外加。"""
	import os
	import map_paint
	if not os.path.isabs(path):
		path = os.path.join(map_paint.ROOT, path)
	rows = map_paint.png_to_rows(path)
	cv = Canvas(len(rows[0]), len(rows))
	cv.grid = [list(r) for r in rows]
	return cv


def vstitch(segments):
	"""纵向关：一段段**从下往上**摞起来（`segments[0]` 是最底下那一段）。
	格子竖着接，装饰、栏杆的行号往下挪；墙上的管道和编号牌按 32 像素一块对齐，纵向关不用。"""
	order = list(reversed(segments))
	rows, props, rails = [], [], []
	offset = 0
	for cv in order:
		if cv.pipes or cv.signs:
			raise SystemExit("纵向关的段里不画管道和编号牌（一段高度不一定是偶数，32 像素一块对不齐）")
		rows += cv.rows()
		props += [(n, c, row + offset) for n, c, row in cv.props]
		rails += [(c0, c1, row + offset) for c0, c1, row in cv.rails]
		offset += cv.height
	return rows, props, {"pipes": [], "signs": [], "rails": rails}
