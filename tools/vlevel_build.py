"""纵向关卡（第四关地下室，往上爬）。由 `level_build.py` 调用：`python tools/level_build.py 4`。

横向关的尺子是「坑跳得过去、墙翻得过去」，纵向关换成：
**每块平台都要能从下面跳上去**（底下 72 以内、横向差 48 以内有个面，中间没被实心块挡住），
以及**从地面一路爬得到顶**（按「往上跳、往下走」做一次连通搜索，每块平台都得搜得到）。

坐标：宽 640（正好一屏，摄像机横向不动）、高 20 屏 = 7200。两侧各一道 32 宽的实心岩墙，
竖井里面是 x 32..608。**一层 60 高**（一屏正好 6 层；一次跳最多上 72，留出余量），
第 i 段（从下往上数，0 是出生那一屏）第 r 层的顶边 y = 7160 - 360·i - 60·(r+1)。
最底下是一整条实心地面（顶边 7160），最上面那一屏是 Boss 区（地板在 y=320，和横向关地面同高）。

段落表在 `level_build.py` 的 `SECTIONS_4`：
  "rows":    [[(x, 宽), ...] × 6]   每一层的单向平台，从下往上
  "blocks":  [(x, 层, 宽)]          实心块（顶边落在那一层的高度，厚 `BLOCK_THICK`）：**不能从下面穿上去**，
                                      要绕着走——这一关的「堵路」。顶上能站
  "enemies": [(类型, 层, x)]        站在那一层上；层写 "b<序号>" 是站在第几块实心块上
             [(类型, ("air", 层), x)]  会飞的，悬在那一层站着的人的身体高度
"""
import os
import struct

import level_build as lb

WIDTH = 640.0
HEIGHT = 7200.0
WALL = 32.0
INSIDE = (WALL, WIDTH - WALL)
GROUND_TOP = HEIGHT - 40.0
ROW = 60.0
ROWS = 6
SCREEN_H = 360.0
LEDGE_THICK = 16.0
## 实心块的厚度。**站在它底下的平台上要留得出一个人**（32 高 + 余量 8）：
## 层距 60，所以最厚 20。厚了的话人站在下一层就顶着它，卡在那儿动不了。
BLOCK_THICK = 20.0
HEAD_ROOM = 40.0
## 一次跳最多往上够多高、横向差多少还够得着（`player.gd` 的跳跃 87 高；
## 上 72 时已经在往下落，横向走了七八十像素，留一半余量）。
MAX_STEP = lb.MAX_STEP
REACH_X = 48.0
SPAWN = (96.0, GROUND_TOP - lb.STAND)
## 出生那一屏不摆敌人；**而且离出生点这么远以内也不放**：西装男会斜着往下打（射程 400），
## 摆在画面外刚好够得着的地方，人一进来就挨冷枪。
SAFE_RADIUS = 420.0
## 会飞的悬在「站在那一层上的人」的身体中心那么高。
AIR_LIFT = lb.STAND


def row_y(section, row):
	return GROUND_TOP - SCREEN_H * section - ROW * (row + 1)


class Surface:
	def __init__(self, name, left, right, top, solid):
		self.name, self.left, self.right, self.top, self.solid = name, left, right, top, solid

	def gap_x(self, other):
		"""两块横向隔多远（重叠就是 0）。"""
		return max(0.0, max(self.left, other.left) - min(self.right, other.right))


class VLevel:
	def __init__(self, sections, enemies, flying, stand_of):
		self.sections = sections
		self.enemy_scenes = enemies
		self.flying = flying
		self.stand_of = stand_of
		self.ledges = []      # (名字, x, 顶边, 宽)
		self.blocks = []      # (名字, x, 顶边, 宽)
		self.enemies = []     # (名字, 类型, x, y)
		self.floating = set()
		self.props = []
		counts = {}

		def name(prefix):
			counts[prefix] = counts.get(prefix, 0) + 1
			return "%s%d" % (prefix, counts[prefix])

		for i, (label, parts) in enumerate(sections):
			for r, row in enumerate(parts.get("rows", [])):
				for x, wide in row:
					self.ledges.append((name("Ledge"), float(x), row_y(i, r), float(wide)))
			section_blocks = []
			for x, r, wide in parts.get("blocks", []):
				block = (name("Block"), float(x), row_y(i, r), float(wide))
				self.blocks.append(block)
				section_blocks.append(block)
			for kind, where, x in parts.get("enemies", []):
				label_ = name(lb.enemy_label(kind) + "-")
				if isinstance(where, tuple):
					y = row_y(i, where[1]) - AIR_LIFT
					self.floating.add(label_)
				elif isinstance(where, str) and where.startswith("b"):
					y = section_blocks[int(where[1:])][2] - stand_of(kind)
				elif where == "g":
					y = GROUND_TOP - stand_of(kind)
				else:
					y = row_y(i, where) - stand_of(kind)
				self.enemies.append((label_, kind, float(x), y))

	def surfaces(self):
		out = [Surface("Ground", INSIDE[0], INSIDE[1], GROUND_TOP, True)]
		out += [Surface(n, x, x + w, top, False) for n, x, top, w in self.ledges]
		out += [Surface(n, x, x + w, top, True) for n, x, top, w in self.blocks]
		return out

	def blocked(self, low, high):
		"""从 low 跳上 high，路上有没有实心块挡着（high 自己不算）。"""
		for n, x, top, w in self.blocks:
			if n == high.name:
				continue
			if x + w <= high.left - 8 or x >= high.right + 8:
				continue
			if top + BLOCK_THICK > high.top - 40 and top < low.top:
				return True
		return False

	def reachable_up(self, low, high):
		step = low.top - high.top
		return 0 < step <= MAX_STEP and low.gap_x(high) <= REACH_X and not self.blocked(low, high)


def check(level):
	problems = []
	faces = level.surfaces()
	for s in faces:
		if s.left < INSIDE[0] - 0.5 or s.right > INSIDE[1] + 0.5:
			problems.append("%s 伸到墙里去了（%.0f..%.0f）" % (s.name, s.left, s.right))
		if s.top < 0:
			problems.append("%s 在关卡顶上面（y %.0f）" % (s.name, s.top))
	# 实心块不许和平台叠在一起（叠着的话那块平台要么站不上、要么人嵌在石头里）
	for n, x, top, w in level.blocks:
		for ln, lx, ltop, lw in level.ledges:
			if lx < x + w and x < lx + lw and ltop < top + BLOCK_THICK and top < ltop + LEDGE_THICK:
				problems.append("%s 和 %s 叠在一起" % (n, ln))
	# 头顶要留得出一个人：平台正上方 40 以内不许有实心块（单向平台不挡人）
	for s in faces:
		for n, x, top, w in level.blocks:
			if n == s.name or x + w <= s.left or x >= s.right:
				continue
			bottom = top + BLOCK_THICK
			if 0 <= s.top - bottom < HEAD_ROOM:
				problems.append("%s 头顶只剩 %.0f 就碰到 %s，站不直" % (s.name, s.top - bottom, n))
	# 每块平台都要能从底下某个面跳上来
	for s in faces[1:]:
		if not any(level.reachable_up(low, s) for low in faces if low is not s):
			problems.append("%s（y %.0f, x %.0f..%.0f）底下没有能跳上来的面" % (s.name, s.top, s.left, s.right))
	# 从地面出发能到每一块：往上跳，或者往下走（掉下去总是可以的）
	seen = {faces[0].name}
	frontier = [faces[0]]
	while frontier:
		here = frontier.pop()
		for s in faces:
			if s.name in seen:
				continue
			up = level.reachable_up(here, s)
			down = s.top > here.top and here.gap_x(s) <= REACH_X
			if up or down:
				seen.add(s.name)
				frontier.append(s)
	lost = [s.name for s in faces if s.name not in seen]
	if lost:
		problems.append("从地面爬不到：%s" % "、".join(lost[:10]))
	top_floor = min(faces, key=lambda s: s.top)
	if top_floor.name not in seen:
		problems.append("爬不到顶（%s）" % top_floor.name)
	# 敌人：出生那一屏、出生点附近不许有；站着的脚下要有面
	first_screen_top = HEIGHT - SCREEN_H
	for name, kind, x, y in level.enemies:
		if y > first_screen_top - 32:
			problems.append("%s 摆在出生那一屏里（y %.0f）" % (name, y))
		if ((x - SPAWN[0]) ** 2 + (y - SPAWN[1]) ** 2) ** 0.5 < SAFE_RADIUS:
			problems.append("%s 离出生点不到 %.0f" % (name, SAFE_RADIUS))
		if not (INSIDE[0] + 12 <= x <= INSIDE[1] - 12):
			problems.append("%s 贴在墙里（x %.0f）" % (name, x))
		if name in level.floating:
			continue
		feet = y + level.stand_of(kind)
		if not any(s.left + 12 <= x <= s.right - 12 and abs(s.top - feet) < 1.0 for s in faces):
			problems.append("%s 站在 (%.0f, %.0f)，脚下没有面（或者半个身子悬在边上）" % (name, x, y))
	return problems


# ---------------------------------------------------------------- 装饰

def prop_width(prop_dir, prop):
	path = os.path.join(lb.HERE, "..", "skins", prop_dir, "props", prop + ".png")
	with open(path, "rb") as f:
		return struct.unpack(">I", f.read(24)[16:20])[0]


def dress(level, prop_dir, small, big, seed, steam="smoke"):
	"""每块平台上摆一两件，地面上多摆几件。自己写的线性同余、固定种子（产物进仓库）。
	装饰要整个落在平台里，不许悬出边。"""
	state = [seed]

	def roll(n):
		state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
		return state[0] % max(1, n)

	def place(left, right, top, pool):
		prop = pool[roll(len(pool))]
		wide = prop_width(prop_dir, prop)
		room = int(right - left - 16 - wide)
		if room < 0:
			return
		level.props.append(("Prop%d" % (len(level.props) + 1), prop, float(left + 8 + roll(room + 1)), top))

	at = INSIDE[0] + 16
	while at < INSIDE[1] - 64:
		place(at, at + 96, GROUND_TOP, big if roll(2) else small)
		at += 96 + roll(48)
	for _, x, top, wide in level.ledges + level.blocks:
		place(x, x + wide, top, small)
		if wide >= 224:
			place(x, x + wide, top, big)
	# **会动的那件不靠抽签**：地面上和每一层歇脚层（宽过 400 的）各摆一团蒸汽。
	# 抽签的话可能一件都抽不中，整关就是死的
	place(INSIDE[0], INSIDE[0] + 200, GROUND_TOP, [steam])
	for _, x, top, wide in level.ledges:
		if wide >= 400:
			place(x, x + wide, top, [steam])


# ---------------------------------------------------------------- 写场景

def build(level, out, root, prop_dir, prop_frames, write):
	ids = {}
	extra = []
	for index, kind in enumerate(sorted({e[1] for e in level.enemies})):
		ids[kind] = "e%d" % index
		extra.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (level.enemy_scenes[kind], ids[kind]))
	prop_ids = {}
	for index, prop in enumerate(sorted({p[1] for p in level.props})):
		prop_ids[prop] = "p%d" % index
		extra.append('[ext_resource type="Texture2D" path="res://skins/%s/props/%s.png" id="%s"]'
			% (prop_dir, prop, prop_ids[prop]))
	extra.append('[ext_resource type="Script" path="res://scripts/prop.gd" id="21"]')
	out_lines = [lb.HEAD + "\n".join(extra) + "\n"]
	out_lines.append('\n[node name="%s" type="Node2D"]\nscript = ExtResource("3")\nfall_y = %g\n'
		% (root, HEIGHT + 40.0))
	out_lines.append('\n[node name="Props" type="Node2D" parent="."]\n')
	for name, prop, x, bottom in level.props:
		out_lines.append('\n[node name="%s" type="Sprite2D" parent="Props"]\n'
			'texture = ExtResource("%s")\n'
			'script = ExtResource("21")\n'
			'position = Vector2(%g, %g)\n' % (name, prop_ids[prop], x, bottom))
		if prop_frames.get(prop, 1) > 1:
			out_lines.append("frames = %d\n" % prop_frames[prop])
	out_lines.append('\n[node name="Level" type="Node2D" parent="."]\n')
	out_lines.append("\n" + lb.platform("Ground", "Level", INSIDE[0], GROUND_TOP, INSIDE[1] - INSIDE[0],
		HEIGHT - GROUND_TOP, skin="terrain_ground"))
	out_lines.append("\n" + lb.platform("WallLeft", "Level", 0, 0, WALL, HEIGHT))
	out_lines.append("\n" + lb.platform("WallRight", "Level", WIDTH - WALL, 0, WALL, HEIGHT))
	for name, x, top, wide in level.ledges:
		out_lines.append("\n" + lb.platform(name, "Level", x, top, wide, LEDGE_THICK, one_way=True))
	for name, x, top, wide in level.blocks:
		out_lines.append("\n" + lb.platform(name, "Level", x, top, wide, BLOCK_THICK))
	out_lines.append('\n[node name="Walls" type="Node2D" parent="Level"]\n')
	out_lines.append('\n[node name="Enemies" type="Node2D" parent="."]\n')
	for name, kind, x, y in level.enemies:
		out_lines.append('\n[node name="%s" parent="Enemies" instance=ExtResource("%s")]\n'
			'position = Vector2(%g, %g)\n' % (name, ids[kind], x, y))
	out_lines.append('\n[node name="Fx" type="Node2D" parent="."]\n'
		'script = ExtResource("13")\n'
		'muzzle_flash_scene = ExtResource("14")\n'
		'hit_spark_scene = ExtResource("15")\n'
		'impact_spark_scene = ExtResource("16")\n'
		'explosion_scene = ExtResource("18")\n')
	out_lines.append('\n[node name="Player" parent="." instance=ExtResource("2")]\n'
		'position = Vector2(%g, %g)\n' % SPAWN)
	out_lines.append('\n[node name="Camera2D" type="Camera2D" parent="."]\n'
		'position = Vector2(%g, %g)\n'
		'script = ExtResource("17")\n'
		'only_up = true\n'
		'limit_left = 0\nlimit_top = 0\nlimit_right = %d\nlimit_bottom = %d\n'
		% (SPAWN[0], SPAWN[1], WIDTH, HEIGHT))
	out_lines.append('\n[node name="HUD" parent="." instance=ExtResource("6")]\n')
	out_lines.append('\n[node name="PauseMenu" parent="." instance=ExtResource("19")]\n')
	out_lines.append('\n[node name="DeathScreen" parent="." instance=ExtResource("20")]\n')
	out_lines.append('\n[node name="ClearScreen" parent="." instance=ExtResource("22")]\n')
	text = "".join(out_lines)
	if write:
		with open(out, "w", newline="\n", encoding="utf-8") as f:
			f.write(text)
	return text
