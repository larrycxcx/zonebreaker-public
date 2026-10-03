"""按格子地图生成关卡（2026-10，分层关卡）。

用户画的示意图定的方向：画面还是连续横向卷动，但场景**上下分层、实心地板隔开、梯子和缺口连通**，
有时得绕路解决问题。原来的 `level_build.py` 是「一条长地面 + 浮台」，表达不了这种结构，
所以换成**一整关一张连续的格子地图**：一格 16 像素、高 23 行（一屏），宽度就是整关的长度，
一段一段（宽度不固定）拼起来。

    #   实心：钢板（地面、墙、楼板）
    X   实心：钢架箱（画面不同，规则和 # 一样）
    %   实心：红色警示条纹（地面上那种）
    ~   实心：传送带，往右带（`BELT_SPEED`）。站在上面的人和敌人被带着走
    -   实心：传送带，往左带
    K   可打爆的箱子（2 格宽）：竖着几行 K 就摞几只（一只 24 高，按 `CRATE_H` 换算），开 4 枪一只。
        找路时**当它不存在**（打烂了就过得去）；挡子弹、挡视线，敌人可以躲在后面
    O   油桶：打一枪就炸（手雷那种爆炸），炸附近的敌人，也炸玩家。不挡路
    !   竖着的红白管子（2 格宽，纯装饰、不挡人，画在背景层）：宣传图左上那种烟囱
    =   单向平台：人从上面踩得住、按下 + 跳能穿下去，子弹穿得过去
    :   单向平台：带支架的钢梁走道（画面不同，规则和 = 一样）
    H   梯子（2 格宽）。最上面那一格所在的那一行就是梯子顶：那层地板在这儿留洞、盖上一块看不见的单向盖子
    P   液压机（左上角，占 2×4 格，吊在正上方的天花板下面）
    G   闸门（左上角，占 2×4 格，上面得是实心的一直到顶——不然跳过去了）
    @   出生点（脚站在下面那一格上）
    >   出口（脚站在下面那一格上）：自检认的终点。没有 Boss 的一段一定要写一个——
        不写的话「最右边那一列能站的地方」都算，中层一直通到右边缘时不爬梯子也「到了」
    B   Boss（脚站在下面那一格上）
    a~z 敌人（每关一张对照表），脚站在下面那一格上
    .   空（空格也算空）

**层高**：一跳 87、最多稳稳地上 4 格（64）。所以两层地板隔 6 格以上（96）就**跳不上去**，
只能靠梯子或缺口——这是分层关卡的骨架。常用的三层：上层地板第 7 行（y 112）、中层第 13 行（y 208）、
地面第 20 行（y 320，和原来的关卡一样高）。中层通道净高 80，液压机（64）正好吊在上层楼板底下。

**自检**（`check()`）在格子上找路：从出生点出发，顺着「走、跳、掉下去、穿过单向平台、爬梯子」能到哪儿，
出口（最右边那一列能站人的地方，或者 Boss）一定要到得了。另外查梯子两头接在地板上、液压机上面有天花板、
闸门上面封顶、敌人站在面上。

    python tools/level_build.py demo     # 生成示意图那一段（scenes/map_demo.tscn），截图给用户看
"""
import os

import level_build as lb

CELL = 16
## 碰撞上都是实心，只是长得不一样（`TileArt` 按材质挑砖）。
SOLIDS = "#X%~-"
## 传送带：字符 → 速度（px/s，正数往右）。玩家走路 180，带 70 是「顶着走慢一截、顺着走快一截」
BELT_SPEED = 70.0
BELTS = {"~": BELT_SPEED, "-": -BELT_SPEED}
CRATE_H = 24
BARREL_H = 22
## 单向平台的两种画法（规则一样）。
ONE_WAYS = "=:"
ROWS = 23
GROUND_ROW = 20
## 一跳最多稳稳地上几格、横着最多跨几格（按 `player.gd` 的数字：跳 87 高、坑最宽 104）。
JUMP_ROWS = 4
JUMP_COLS = 6
## 隔着空当往下跳，最多低几格还算（再低就是「掉下去」，走边缘那条路已经算了）
DROP_ROWS = 6
## 人有多高（格）：站的地方上面这么多格得是空的。
BODY_ROWS = 2
TRAP_COLS = 2
TRAP_ROWS = 4
LADDER_COLS = 2
## 出生那一屏（44 格 = 704 像素，和横向关的 `SAFE_START` 700 一样）不许摆敌人。
SAFE_COLS = 44


class MapLevel:
	"""把格子地图读成几何：实心矩形、单向平台、梯子、机关、敌人、出生点。"""

	def __init__(self, rows, letters, scenes, stand_of, floating=(), hanging=()):
		"""`letters`：地图里的小写字母 → 敌人类型（`"c": "2_c"`，Boss 用键 `"boss"`）；
		`scenes`：敌人类型 → 场景路径（就是 `level_build.py` 里每关那张 `ENEMIES_x`）。"""
		width = max(len(r) for r in rows)
		self.grid = [r.ljust(width, ".").replace(" ", ".") for r in rows]
		if len(self.grid) != ROWS:
			raise SystemExit("格子地图要正好 %d 行（现在 %d 行）" % (ROWS, len(self.grid)))
		self.width = width
		self.letters = letters
		self.enemy_scenes = scenes
		## 会飞的（直升机、飘着的 Boss）：摆在那一格的正中，脚下不用有地。
		self.floating = set(floating)
		## 吊在画面顶上等着砸下来的（第二关 2-A）：不管写在第几行，都摆到画面以上（`lb.HANG_Y`）。
		self.hanging = set(hanging)
		self.stand_of = stand_of
		self.solids = []      # (名字, x, y, 宽, 高)   单位：像素
		self.ledges = []      # (名字, x, y, 宽)
		self.ladders = []     # (名字, 中线 x, 顶 y, 高)
		self.presses = []     # (名字, x, y, 天花板 y, 错开几秒)
		self.gates = []       # (名字, x, y, 错开几秒)
		self.belts = []       # (名字, x, y, 宽, 高, 速度)
		self.crates = []      # (名字, 左上 x, 左上 y)
		self.barrels = []     # (名字, 中心 x, 中心 y)
		self.enemies = []     # (名字, 类型, x, y)
		self.props = []
		self.spawn = None
		self.exit_cell = None
		self.boss_cell = None
		self._read()

	def at(self, r, c):
		if c < 0 or c >= self.width:
			return "#"          # 关卡左右两头是墙
		if r < 0:
			return "."
		if r >= ROWS:
			return "#"
		return self.grid[r][c]

	def solid(self, r, c):
		return self.at(r, c) in SOLIDS

	def _read(self):
		counts = {}

		def name(prefix):
			counts[prefix] = counts.get(prefix, 0) + 1
			return "%s%d" % (prefix, counts[prefix])

		# 实心：每一行先找横着的一段段，再把上下相同的段合成一块（少几百个节点）
		# 传送带各自成块（每块带自己的速度），不和别的实心合并
		plain = SOLIDS.translate({ord(b): None for b in BELTS})
		runs = {}
		for r in range(ROWS):
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
		# 单向平台：每一行横着的一段
		for r in range(ROWS):
			c = 0
			while c < self.width:
				if self.grid[r][c] in ONE_WAYS:
					start = c
					while c < self.width and self.grid[r][c] in ONE_WAYS:
						c += 1
					self.ledges.append((name("Ledge"), start * CELL, r * CELL, (c - start) * CELL))
				else:
					c += 1
		# 梯子：竖着连在一起的 H（2 格宽，按左边那一列认）
		seen = set()
		for c in range(self.width):
			for r in range(ROWS):
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
		# 箱子：竖着连在一起的 K（2 格宽，按左边那一列认），从底往上摞
		seen = set()
		for c in range(self.width):
			for r in range(ROWS):
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
		# 机关、敌人、出生点、Boss
		press_index = 0
		for r in range(ROWS):
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
				elif ch == "O":
					self.barrels.append((name("Barrel"), x, feet - BARREL_H / 2.0))
				elif ch == "@":
					self.spawn = (x, feet - lb.STAND)
				elif ch == ">":
					self.exit_cell = (r + 1, c)
				elif ch == "B" or ch.islower():
					kind = self.letters.get("boss" if ch == "B" else ch)
					if kind is None:
						raise SystemExit("格子地图里的敌人字母 %r 在对照表里没有" % ch)
					label = name(lb.enemy_label(kind) + "-")
					if kind in self.hanging:
						y = lb.HANG_Y
					elif kind in self.floating:
						y = r * CELL + CELL / 2.0
					else:
						y = feet - self.stand_of(kind)
					self.enemies.append((label, kind, x, y))
					if ch == "B":
						self.boss_cell = (r, c)

	# ------------------------------------------------------------ 找路

	def body_free(self, r, c):
		"""脚站在第 r 行那一格上、身子占上面 BODY_ROWS 格：那几格不能是实心的。"""
		return all(not self.solid(r - k, c) for k in range(1, BODY_ROWS + 1))

	def supports(self, r, c):
		return self.solid(r, c) or self.at(r, c) in ONE_WAYS or self._ladder_top(r, c)

	def _ladder_top(self, r, c):
		return self.at(r, c) == "H" and self.at(r - 1, c) != "H"

	def standable(self, r, c):
		# 地图底下那一行以下算实心（掉不出去），但**站不上去**——不然坑底就成了一条能走的路
		# （往下跳那条加上以后，找路从坑底一路走过了第一关的大坑，拆掉梯子自检照样绿）
		return 0 <= c < self.width and r < ROWS and self.supports(r, c) and self.body_free(r, c)

	def _land(self, r, c):
		"""从第 r 行往下掉（身子在 r 往上），落在哪一行（第一个能站的面）。掉出地图就是 None。"""
		while r < ROWS:
			if self.solid(r - 1, c):
				return None   # 身子卡进实心里了，不算
			if self.supports(r, c):
				return r
			r += 1
		return None

	def is_pit(self, r, c):
		"""从第 r 行走到第 c 列这一格（这一格站不住）：是掉出关卡的坑吗？
		身子被实心挡着的是墙、不是坑；往下能落到任何一个面上（哪怕是更低的一层）也不是坑。"""
		if not self.body_free(r, c):
			return False
		return not any(self.supports(rr, c) for rr in range(r, ROWS))

	def moves(self, r, c):
		out = []
		# 走：左右一格，同一行接着能站
		for dc in (-1, 1):
			if self.standable(r, c + dc):
				out.append((r, c + dc))
			elif 0 <= c + dc < self.width and self.body_free(r, c + dc):
				# 走出边缘：从旁边那一列掉下去
				land = self._land(r + 1, c + dc)
				if land is not None:
					out.append((land, c + dc))
		# 穿下单向平台：站在 = 上按下 + 跳
		if self.at(r, c) in ONE_WAYS:
			land = self._land(r + 1, c)
			if land is not None:
				out.append((land, c))
		# 跳：往上最多 JUMP_ROWS 格、横着最多 JUMP_COLS 格；头顶那一片不能有实心。
		# 也能**往下跳到一块更低的台子**（最多低 DROP_ROWS 格，落得越低滞空越久，横着只会更远，按 JUMP_COLS 算是保守的）——
		# 第一版只算了平跳和往上跳，隔着坑往下一级台子跳就被当成「到不了」（第一关空中那一串台子）
		for up in range(-DROP_ROWS, JUMP_ROWS + 1):
			for dc in range(-JUMP_COLS, JUMP_COLS + 1):
				tr, tc = r - up, c + dc
				if (up == 0 and abs(dc) <= 1) or not self.standable(tr, tc):
					continue
				if self._arc_clear(r, c, tr, tc):
					out.append((tr, tc))
		# 梯子：在梯子底下 / 梯子顶上，上下两头连通
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
		"""从 (r, c) 跳到 (tr, tc)：跳起来那一截（起点正上方，到最高点）和落下来那一截都不能撞上实心的。
		单向平台不挡往上跳。

		路线按三截算：起点那一列从脚下升到最高点、在最高点横着过去、终点那一列从最高点落到落脚的那一格。
		最高点至少比两头都高 1 格，最多比起点高 `JUMP_ROWS` 格——试遍这几档，有一档走得通就行，
		所以**跳得过比最高点矮的障碍**（屋顶上的箱子、坑边的矮沿），也落得到一个箱子**上面**
		（第一版把整个矩形都当成要空着的，落脚的那块箱子本身就把自己挡住了）。"""
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
	"""`chasers`：会冲过来的那几种（冲撞、自爆、落地就冲的）——它们脚下那条路的两头**不许是坑**：
	用户试玩看到的「冲刺的敌人还没到跟前就自己掉坑里了」。
	`min_enemies`：出生那一屏以外，每一屏（40 格）至少几个敌人——不许出现大片空着、只是一直往前跑的地方。"""
	problems = []
	if level.spawn is None:
		problems.append("没有出生点（@）")
		return problems
	sr = int((level.spawn[1] + lb.STAND) // CELL)
	if not level.standable(sr, int(level.spawn[0] // CELL)):
		problems.append("出生点脚下没有能站的面")
	seen = level.reachable()
	# 终点：Boss 跟前（飘着的 Boss 就是它底下那一片能站的地方），或者标了 > 的出口
	if level.boss_cell is not None:
		br, bc = level.boss_cell
		goal = {(r, cc) for r in range(br + 1, ROWS) for cc in range(bc - 12, bc + 13) if level.standable(r, cc)}
	elif level.exit_cell is not None:
		goal = {level.exit_cell}
	else:
		problems.append("没有终点：要么摆 Boss（B），要么标出口（>）")
		goal = set()
	if goal and not goal & seen:
		problems.append("从出生点到不了终点（%s）" % ("Boss" if level.boss_cell else "出口 >"))
	# 梯子：两头都要接在能站的面上
	for name, x, top, height in level.ladders:
		c = int((x - CELL) // CELL)
		bottom_row = int((top + height) // CELL)
		if not level.solid(bottom_row, c) and level.at(bottom_row, c) not in ONE_WAYS:
			problems.append("%s 底下没接到地板（第 %d 行）" % (name, bottom_row))
		top_row = int(top // CELL)
		beside = [level.at(top_row, c - 1), level.at(top_row, c + LADDER_COLS)]
		if not any(b in SOLIDS + ONE_WAYS for b in beside):
			problems.append("%s 顶上两边都没有地板，它通到哪儿去？" % name)
	# 液压机：上面要有天花板；底边落在实心或者单向平台上
	for name, x, y, ceiling, _ in level.presses:
		c, r = int(x // CELL), int(y // CELL)
		if ceiling <= 0 and not level.solid(-1, c):
			problems.append("%s 上面没有天花板（吊在哪儿？）" % name)
		if level.at(r + TRAP_ROWS, c) not in SOLIDS + ONE_WAYS:
			problems.append("%s 底下没有地板" % name)
	# 闸门：门正上方得一直是实心的，直到接上一整层天花板（门两边也都是实心的那一行）或者画面顶——
	# 门 64 高、一跳 87，中间留个缝就跳过去了。在厂房里接的是天花板，在露天就得一直封到顶
	for name, x, y, _ in level.gates:
		c, r = int(x // CELL), int(y // CELL)
		sealed = True
		for rr in range(r - 1, -1, -1):
			if not (level.solid(rr, c) and level.solid(rr, c + 1)):
				sealed = False
				break
			if level.solid(rr, c - 1) and level.solid(rr, c + 2):
				break
		if not sealed:
			problems.append("%s 上面没有封顶，跳得过去" % name)
		if not level.solid(r + TRAP_ROWS, c):
			problems.append("%s 底下没有地板" % name)
	for name, x, y in level.crates:
		c, r = int(x // CELL), int((y + CRATE_H) // CELL)
		if not (level.supports(r, c) or level.at(r, c) == "K"):
			problems.append("%s 底下悬空" % name)
	for name, x, y in level.barrels:
		c, r = int(x // CELL), int((y + BARREL_H / 2.0) // CELL)
		if not level.supports(r, c):
			problems.append("%s 底下悬空" % name)
	for label, kind, x, y in level.enemies:
		if kind not in chasers:
			continue
		c = int(x // CELL)
		if kind in level.hanging:
			# 吊着的落地之后才冲：查它砸下去落到的那一层
			r = next((rr for rr in range(ROWS) if level.standable(rr, c)), None)
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
				problems.append("%s（会冲的）脚下这条路%s头是坑（第 %d 列），没冲到玩家跟前自己先掉下去"
					% (label, "左" if step < 0 else "右", beyond))
	if min_enemies:
		screens = level.width // 40
		# Boss 区那两屏（Boss 那一屏和它前面一屏）不算：那儿是单挑
		if level.boss_cell is not None:
			screens = min(screens, level.boss_cell[1] // 40 - 1)
		for screen in range(1, screens):
			count = sum(1 for e in level.enemies if screen * 40 * CELL <= e[2] < (screen + 1) * 40 * CELL)
			if count < min_enemies:
				problems.append("第 %d 屏只有 %d 个敌人（至少 %d 个）" % (screen + 1, count, min_enemies))
	# 敌人：出生那一屏不许有（人一进来就挨打）；站着的脚下能站、身子不嵌在墙里；
	# 吊着的那一列底下得有地（掉下来要落得住）；会飞的不嵌在墙里
	for label, kind, x, y in level.enemies:
		c = int(x // CELL)
		if x < safe_cols * CELL:
			problems.append("%s 摆在出生那一屏里（第 %d 列）" % (label, c))
		if kind in level.hanging:
			if not any(level.standable(r, c) for r in range(ROWS)):
				problems.append("%s 吊着的那一列底下没有地，掉下来就摔死了" % label)
			continue
		if kind in level.floating:
			if level.solid(int(y // CELL), c):
				problems.append("%s 飘在墙里" % label)
			continue
		r = int((y + level.stand_of(kind)) // CELL)
		if not level.standable(r, c):
			problems.append("%s 站在 (%d, %d) 格，脚下没有面或者身子嵌在墙里" % (label, r, c))
	return problems


# ---------------------------------------------------------------- 画面：砖（2026-10，用户要求「尽量接近宣传图、多些结构和细节」）
#
# 碰撞还是那些平台节点（在地图生成的关卡里藏起来、不画），画面交给 `TileArt`：
# 一格画一块 32×32 砖的四分之一，哪一块、哪个角按这一格在那块实心区域里的位置挑（顶边、侧边、拐角、内部）。
# 砖的编号是工业区素材 `1 Tiles/IndustrialTile_NN.png` 的编号（`terrain_build.py` 把 81 块排成一张总图）。

## 每种材质的九宫格：(顶, 中, 底) × (左, 中, 右)。钢板那套是按接缝认出来的（4/5/6、13/14/15、22/23/24，14 四面都能接自己）。
NINE = {
	"#": ((4, 5, 6), (13, 14, 15), (22, 23, 24)),
	"%": ((58, 59, 60), (67, 68, 69), (67, 68, 69)),
	"~": ((74, 75, 76), (13, 14, 15), (22, 23, 24)),
	"-": ((74, 75, 76), (13, 14, 15), (22, 23, 24)),
	"=": ((77, 78, 79), (77, 78, 79), (77, 78, 79)),
	":": ((18, 18, 27), (18, 18, 27), (18, 18, 27)),
}
## 钢架箱：一整块就是一个箱子，按 32 像素的格子对齐、四个角各取一角。
CRATES = (36, 62)
## 室内的背景墙：大多是平的深色墙板，夹几块带面板 / 横条的（按 32 像素一块随机挑，固定种子）。
BACK_TILES = [(21, 12), (3, 2), (47, 1)]
## 竖着的红白管子（`!`）：最上面那一节是带顶的（45），往下交替（54 / 63）。
PIPE_TOP = 45
PIPE_BODY = (54, 63)
## 室内地板上自动撒的装饰（工业区的 props），以及大约每隔几格摆一件。
## 不撒红色的 `barrel`：它和**会炸的油桶**是同一张图，摆一堆不会炸的会让玩家分不清（2026-10 截图看出来的）。
## 也不撒 `locker` / `board`：那两张是挂在墙上的东西，贴图底边离画布底 7~9 像素，摆在地上是飘着的——要用就在地图里点名挂到墙上。
INDOOR_PROPS = ["box", "extinguisher", "bucket", "box_open", "barrel_rust", "crate"]
PROP_STEP = (5, 11)
## 露天的地面上也撒（2026-10 用户：「尽量不出现大面积空旷的场景」），换一套露天该有的东西
OUTDOOR_PROPS = ["barrel_rust", "box", "warning", "bucket", "crate", "box_open", "bench"]
## 总图一行几块（工业区 9、绿区 12），背景墙压暗多少。
COLUMNS = 9
BACK_TINT = (0.72, 0.72, 0.8)

## **每个区一套砖**（2026-10 做第一关时拆出来的）：上面那些常量就是工业区那套，`use_theme()` 换成别的区。
## 绿区（第一关，`green-zone-tileset/Tileset.png`，12 列，编号 = 行 × 12 + 列 + 1）是**按四条边上的黑描边认出来的**：
##   草皮整块 1/2/3、13/14/16、25/26/28；石砖顶 9/10/12，石砖身子是带砖纹的暗块 53/54/41，底 67/27/68；
##   单行草皮浮台（底边垂着土）49/50/51、单行石台 44/45/46；一整块石头 30；一格宽的草皮柱子 5/17/29。
##   暗紫色填充 + 稀疏砖纹（54、55、37~40）就是**洞里的墙**——绿区的「室内」是地下的山洞。
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
		# 大多是平的暗块（19 / 20），夹几块带青苔的（54 / 55）：青苔那块一格一格重复太抢眼（截图看出来的）
		"BACK_TILES": [(19, 8), (20, 6), (54, 2), (55, 1)],
		# `!` 在绿区是背景里的草皮石柱（一格宽那套：带草的顶 + 身子）
		"PIPE_TOP": 5, "PIPE_BODY": (17, 17),
		# 不撒 `box`：绿区可打爆的箱子就是这张图（`cyberpunk_trap_crate.tscn`），摆一堆打不烂的会让人分不清
		"INDOOR_PROPS": ["rock_small", "rock", "bin", "rock_small", "grass_tuft"],
		"OUTDOOR_PROPS": ["grass_tuft", "grass_blade", "bush_flat", "rock_small", "grass_tuft", "bush_big",
			"bench", "rock", "grass_blade", "bin"],
		"COLUMNS": 12, "BACK_TINT": (0.8, 0.8, 0.86),
	},
	## 酒吧街（第三关，`bar-street-tileset/1 Tiles/Tiles_01..100`，10 列）：
	##   地面和楼板 = 带木梁顶的棕砖（1/2/4、11/12/14、21/22/24，按黑描边认的）；单行的木梁砖 31/32/34 当单向的楼板（`:`）；
	##   浮台 = 蓝色条纹雨棚 7/8/9（和横向那版一样：在街上踩着店家的雨棚跳）；
	##   堵路的墙 = 拉下来的蓝色卷帘（顶 29/28/30、身子 39/38/40）——「卷帘门」本身就是此路不通；
	##   一整块的棕砖 44 当掩体；**室内**（楼里）是灰砖墙 60，夹几块带裂缝的 70/80/90；`!` 是灰色水管 79/89。
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
		# 酒瓶、酒杯、飞钞、飘牌不要（像能捡的东西，见 CLAUDE.md）；`bin`（其实是一个牛头骨）和 `crate`
		# （一把平放的刀）也不撒——小小一个摆满地板，截图上看着就是一地能捡的东西
		"INDOOR_PROPS": ["stool", "keg", "stool2", "keg"],
		# 霓虹招牌（`sign` / `sign2`）是挂墙上的，不撒在地上——要用就在地图里点名挂高
		"OUTDOOR_PROPS": ["keg"],
		"COLUMNS": 10, "BACK_TINT": (0.75, 0.75, 0.8),
	},
}


def use_theme(name):
	"""换成某个区的那套砖和装饰（模块里的常量直接换掉，后面的代码照常读）。"""
	global NINE, CRATES, BACK_TILES, PIPE_TOP, PIPE_BODY, INDOOR_PROPS, OUTDOOR_PROPS, COLUMNS, BACK_TINT
	t = THEMES[name]
	NINE, CRATES, BACK_TILES = t["NINE"], t["CRATES"], t["BACK_TILES"]
	PIPE_TOP, PIPE_BODY = t["PIPE_TOP"], t["PIPE_BODY"]
	INDOOR_PROPS, OUTDOOR_PROPS = t["INDOOR_PROPS"], t["OUTDOOR_PROPS"]
	COLUMNS, BACK_TINT = t["COLUMNS"], t["BACK_TINT"]


def _hash(a, b, seed):
	return ((a * 73856093) ^ (b * 19349663) ^ seed) & 0x7FFFFFFF


def tile_cells(level, seed=20261003):
	"""算出前景（实心、单向）和背景（室内的墙）每一格画哪块砖的哪个角。返回 (前景, 背景) 两个扁平的整数表。"""
	front, back = [], []
	for r in range(ROWS):
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
	"""这一格头顶上（同一列往上）有**实心的**楼板 / 天花板吗——有就是室内，铺背景墙。
	单向平台不算：露天的钢梁走道底下还是露天（第一版算上了，走道底下一块块深色墙，截图一眼就看出来）。"""
	for rr in range(r - 1, -1, -1):
		if level.solid(rr, c):
			return True
	return False


# ---------------------------------------------------------------- 贴花：管道、编号牌（墙上的）；栏杆（楼板上的）
#
# 素材里那组紫色几何砖是**一套管道网**（按四条边上紫色在哪几段认出来的）：
# 20 横管、1 竖管、38 / 30 横管的左头 / 右头、10 / 28 竖管的上头 / 下头、39 带大圆盘的接头（四面都接粗管）。
# 宣传图墙上那条大紫管就是「管头 → 横管 → 圆盘 → ……」连起来的；圆盘上叠一个数字（`3 Objects/0~9.png`）就是编号牌。
# 管道按 **32 像素一块** 的坐标给拐点（一块 = 2×2 格），只能横平竖直；画在室内墙那一层上面（管砖自带深色底）。
PIPE_BY_DIRS = {
	frozenset("EW"): 20, frozenset("NS"): 1,
	frozenset("E"): 38, frozenset("W"): 30, frozenset("S"): 10, frozenset("N"): 28,
}
PIPE_JOINT = 39


def pipe_blocks(pipes, signs):
	"""把每条管道（拐点列表，块坐标）摊成「这一块往哪几个方向接」，返回 {块: 砖编号}。
	拐角、分叉、编号牌那一块都画圆盘接头。"""
	dirs = {}
	for path in pipes:
		for (x0, y0), (x1, y1) in zip(path, path[1:]):
			if x0 != x1 and y0 != y1:
				raise SystemExit("管道只能横平竖直：%s -> %s" % ((x0, y0), (x1, y1)))
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
	"""管道、编号牌的砖（四分之一一格，和 `TileArt` 的格式一样）。"""
	cells = []
	for (bx, by), tile in sorted(pipe_blocks(pipes, signs).items()):
		for q in range(4):
			cells += [bx * 2 + q % 2, by * 2 + q // 2, tile, q]
	return cells


def rail_props(rails):
	"""栏杆：(从第几列, 到第几列, 站在第几行)。左端、中段、右端各 32 宽，按 2 格一节拼。"""
	out = []
	for c0, c1, row in rails:
		cols = list(range(c0, c1 + 1, 2))
		for i, c in enumerate(cols):
			prop = "fence" if i == 0 else ("fence_end" if i == len(cols) - 1 else "fence_mid")
			out.append((prop, c, row))
	return out


def dress(level, named, seed=20261003):
	"""装饰：先摆地图里点名的（`named`：(装饰名, 列, 站在第几行)），再在地板上自动撒（室内、露天各一套）。
	撒的时候躲开梯子、机关和敌人那几格，装饰之间至少隔几格。"""
	# 整栋的楼面（酒吧街的 `facade_N`）排最前、画在最后面：不然一栋楼会把先摆的吧台、招牌盖住
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
	for _, x, _, _ in level.gates:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 3))
	for _, x, _ in level.crates:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 3))
	for _, x, _ in level.barrels:
		busy.update(range(int(x // CELL) - 1, int(x // CELL) + 2))
	taken = {(int(p[2] // CELL), int(p[3] // CELL)) for p in level.props}
	enemy_cells = {(int(x // CELL), int((y + 16) // CELL)) for _, _, x, y in level.enemies}
	state = [seed]

	def roll(n):
		state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
		return state[0] % max(1, n)

	for r in range(ROWS):
		c = 0
		next_at = roll(PROP_STEP[1])
		while c < level.width:
			# 不撒在钢架箱 / 石块（X）上：那是一块块掩体，顶上摆张长椅看着像叠罗汉
			floor = level.solid(r, c) and not level.solid(r - 1, c) and level.body_free(r, c) \
				and level.at(r, c) != "X"
			if floor and c >= next_at and c not in busy and (c, r) not in taken \
					and not any((cc, r) in enemy_cells for cc in range(c - 2, c + 3)):
				pool = INDOOR_PROPS if _indoor(level, r - 1, c) else OUTDOOR_PROPS
				prop = pool[roll(len(pool))]
				level.props.append(("Prop%d" % (len(level.props) + 1), prop, c * CELL, r * CELL))
				next_at = c + PROP_STEP[0] + roll(PROP_STEP[1] - PROP_STEP[0])
			c += 1


# ---------------------------------------------------------------- 写场景

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
	extra.append('[ext_resource type="Texture2D" path="res://skins/%s/tiles/atlas.png" id="tb"]' % prop_dir)
	extra.append('[ext_resource type="Script" path="res://scripts/prop.gd" id="21"]')
	prop_ids = {}
	for index, prop in enumerate(sorted({p[1] for p in level.props} | {"digit_%d" % d for d, _, _ in signs})):
		prop_ids[prop] = "p%d" % index
		extra.append('[ext_resource type="Texture2D" path="res://skins/%s/props/%s.png" id="%s"]'
			% (prop_dir, prop, prop_ids[prop]))
	if level.presses:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t0"]' % lb.PRESS_SCENE)
	if level.gates:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t1"]' % lb.GATE_SCENE)
	if level.belts:
		extra.append('[ext_resource type="Script" path="res://scripts/belt_art.gd" id="bl"]')
	if level.crates:
		extra.append('[ext_resource type="PackedScene" path="res://scenes/trap_crate.tscn" id="t3"]')
	if level.barrels:
		extra.append('[ext_resource type="PackedScene" path="res://scenes/trap_barrel.tscn" id="t4"]')
	width = level.width * CELL
	# 总图一行几块：工业区是 TileArt 的默认值 9，不写；别的区写出来
	columns_line = "" if COLUMNS == 9 else "columns = %d\n" % COLUMNS
	lines = [lb.HEAD + "\n".join(extra) + "\n"]
	lines.append('\n[node name="%s" type="Node2D"]\nscript = ExtResource("3")\n' % root)
	# 画的顺序：背景（视差那几层，关卡加载时插到最前面）→ 室内的墙 → 装饰 → 实心的砖 → 平台（藏着）→ 机关 → 敌人
	lines.append('\n[node name="BackTiles" type="Node2D" parent="."]\nscript = ExtResource("ta")\n'
		'atlas = ExtResource("tb")\n%stint = Color(%g, %g, %g, 1)\ncells = PackedInt32Array(%s)\n'
		% ((columns_line,) + tuple(BACK_TINT) + (", ".join(str(v) for v in back),)))
	# 编号牌上的数字：贴在圆盘正中，画在墙那一层上面
	lines.append('\n[node name="Decals" type="Node2D" parent="."]\n')
	for i, (digit, bx, by) in enumerate(signs):
		lines.append('\n[node name="Sign%d" type="Sprite2D" parent="Decals"]\ntexture = ExtResource("%s")\n'
			'position = Vector2(%g, %g)\n' % (i + 1, prop_ids["digit_%d" % digit], bx * 32 + 16, by * 32 + 16))
	lines.append('\n[node name="Props" type="Node2D" parent="."]\n')
	for name, prop, x, bottom in level.props:
		lines.append('\n[node name="%s" type="Sprite2D" parent="Props"]\n'
			'texture = ExtResource("%s")\nscript = ExtResource("21")\nposition = Vector2(%g, %g)\n'
			% (name, prop_ids[prop], x, bottom))
		if prop_frames and prop_frames.get(prop, 1) > 1:
			lines.append("frames = %d\n" % prop_frames[prop])
	lines.append('\n[node name="FrontTiles" type="Node2D" parent="."]\nscript = ExtResource("ta")\n'
		'atlas = ExtResource("tb")\n%scells = PackedInt32Array(%s)\n' % (columns_line, ", ".join(str(v) for v in front)))
	# 传送带中间那一截的齿朝它带的方向滚（`BeltArt`），盖在砖上面
	if level.belts:
		lines.append('\n[node name="Belts" type="Node2D" parent="."]\nscript = ExtResource("bl")\n'
			'atlas = ExtResource("tb")\nbelts = PackedFloat32Array(%s)\n'
			% ", ".join("%g, %g, %g, %g" % (x, y, w, speed) for _, x, y, w, _, speed in level.belts))
	lines.append('\n[node name="Level" type="Node2D" parent="."]\n')
	for name, x, y, w, h in level.solids:
		# 画面交给砖（`TileArt`），平台只管碰撞，所以藏起来
		lines.append("\n" + lb.platform(name, "Level", x, y, w, h) + "visible = false\n")
	for name, x, y, w, h, speed in level.belts:
		lines.append("\n" + lb.platform(name, "Level", x, y, w, h) + "visible = false\nconveyor = %g\n" % speed)
	lines.append("\n" + lb.platform("WallLeft", "Level", -16, 0, 16, lb.SCREEN_H))
	lines.append("\n" + lb.platform("WallRight", "Level", width, 0, 16, lb.SCREEN_H))
	for name, x, y, w in level.ledges:
		lines.append("\n" + lb.platform(name, "Level", x, y, w, 16, one_way=True) + "visible = false\n")
	for name, x, top, height in level.ladders:
		lines.append('\n[node name="%s" parent="Level" instance=ExtResource("t2")]\n'
			'position = Vector2(%g, %g)\nheight = %g\n' % (name, x, top, height))
	lines.append('\n[node name="Walls" type="Node2D" parent="Level"]\n')
	if level.presses or level.gates or level.crates or level.barrels:
		lines.append('\n[node name="Traps" type="Node2D" parent="."]\n')
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
		'script = ExtResource("17")\n'
		'limit_left = 0\nlimit_top = 0\nlimit_right = %d\nlimit_bottom = %d\n'
		% (level.spawn[0], level.spawn[1], width, lb.SCREEN_H))
	lines.append('\n[node name="HUD" parent="." instance=ExtResource("6")]\n')
	lines.append('\n[node name="PauseMenu" parent="." instance=ExtResource("19")]\n')
	lines.append('\n[node name="DeathScreen" parent="." instance=ExtResource("20")]\n')
	lines.append('\n[node name="ClearScreen" parent="." instance=ExtResource("22")]\n')
	text = "".join(lines)
	if write:
		with open(out, "w", newline="\n", encoding="utf-8") as f:
			f.write(text)
	return text
