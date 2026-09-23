"""按一份段落描述生成正式关卡场景，输出到 scenes/level_1.tscn。

    python tools/level_build.py          # 生成
    python tools/level_build.py --check  # 只自检，不写文件

**为什么用脚本生成**：正式关卡 12800 宽 = 20 屏，手写几百个节点没法迭代——
调一下节奏就要重排一整屏。这里只改下面那张 `SECTIONS` 表，重跑一遍就行。
和 `skin_build.py` 那套是一个路子：规则和数字写在脚本里，产物进仓库。

**关卡用的还是 `platform.tscn`，没换 TileMap**：墙挡子弹、单向平台、矮通道净空
这些规则和测试全绑在它身上，地形贴图本来就是按大小九宫格平铺的，多长都行。

一段 = 1280 宽（两屏）。段里的坐标写**段内相对值**，拼接时自动加上段的起点。
生成时会自检（见 `check_level()`）：坑跳得过去、矮通道净空还是 30、墙翻得过去、
浮台够得着、敌人没摆在坑上或矮通道底下。数字不对直接报错，不会悄悄产出一个过不去的关卡。
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "scenes", "level_1.tscn")

# ---------------------------------------------------------------- 关卡的尺子

## 一段多宽（两屏）。
SECTION = 1280
## 地面顶边的 y，以及地面画多厚。
GROUND_Y = 320.0
GROUND_THICK = 40.0
## 画面多高。摄像机的 limit_bottom 用它。
SCREEN_H = 360.0
## 站在地上的敌人 / 玩家的 y：判定框 32 高、原点在正中，所以是地面顶边往上 16。
STAND = 16.0
## Boss A 的判定框 48 高，原点在正中 → 顶边往上 24。
BOSS_STAND = 24.0
## 飞行的 E 悬停高度。
FLY_Y = 88.0

## 玩家的本事（`player.gd` 里的数字算出来的，改那边要跟着改这里）：
## 跳跃 v=560、重力 g=1800 → 跳得起 560²/(2×1800) ≈ 87px，滞空 2×560/1800 ≈ 0.62 秒。
JUMP_HEIGHT = 87.0
AIR_TIME = 0.62
WALK_SPEED = 180.0
## 坑最宽多少：走着跳（不冲刺）跳得过去的距离，再留一截余量。
MAX_GAP = WALK_SPEED * AIR_TIME - 8.0      # ≈ 103
## 浮台一次最多往上跳多高：跳跃高度留 15px 余量。
MAX_STEP = JUMP_HEIGHT - 15.0              # 72
## 墙最高多少：CLAUDE.md 的规矩是比跳跃高度至少低 12。
MAX_WALL = JUMP_HEIGHT - 12.0              # 75
## 矮通道净空：站着 32 过不去、站姿子弹 25 过得去，窗口只有几个像素（见 CLAUDE.md）。
CRAWL_CLEAR = 30.0
## 矮通道那块砖画多厚。
CRAWL_THICK = 50.0

## 敌人类型 → 场景路径。键就是 `SECTIONS` 里写的名字。
ENEMIES = {
	"walker_a": "res://scenes/enemy_walker_a.tscn",
	"walker_b": "res://scenes/enemy_walker_b.tscn",
	"walker_c": "res://scenes/enemy_walker_c.tscn",
	"walker_f": "res://scenes/enemy_walker_f.tscn",
	"turret": "res://scenes/enemy_turret.tscn",
	"chaser_d": "res://scenes/enemy_chaser.tscn",
	"flyer_e": "res://scenes/enemy_flyer.tscn",
	"boss_a": "res://scenes/boss_a.tscn",
}

# ---------------------------------------------------------------- 第一关的段落
#
# 每段：(名字, {
#   "gaps":   [(段内 x, 宽)]            地面在这儿断开 —— 掉下去就死
#   "ledges": [(段内 x, 顶边 y, 宽)]     单向浮台，从下面能穿上去
#   "walls":  [(段内 x, 高)]            实心竖墙，挡路挡子弹，巡逻兵碰到掉头
#   "crawl":  [(段内 x, 宽)]            矮通道顶块，底下只剩 30px，必须趴着爬
#   "enemies":[(类型, 段内 x, 站在哪个顶边上)]
# })
#
# 「站在哪个顶边上」写的是**脚下那个面的 y**（地面就是 GROUND_Y，浮台就是它的顶边），
# 生成时自动换算成敌人的原点高度；飞行的 E 写 None。

SECTIONS = [
	("Warmup", {                                  # 热身：认识一下走、跳、开枪
		"ledges": [(320, 256, 96), (600, 256, 96)],
		"enemies": [("walker_a", 500, GROUND_Y), ("walker_a", 900, GROUND_Y),
			("walker_a", 1150, GROUND_Y)],
	}),
	("Stairs", {                                  # 阶梯往上，边跳边挨打
		"ledges": [(120, 264, 96), (280, 216, 96), (440, 176, 128)],
		"walls": [(700, 56)],
		"enemies": [("walker_b", 500, 176), ("turret", 820, GROUND_Y),
			("walker_a", 1080, GROUND_Y)],
	}),
	("Crawl", {                                   # 矮通道：必须趴着爬过炮台的火线
		"crawl": [(200, 200)],
		"ledges": [(840, 248, 96)],
		"enemies": [("turret", 540, GROUND_Y), ("flyer_e", 440, None),
			("walker_a", 1040, GROUND_Y), ("walker_c", 1220, GROUND_Y)],
	}),
	("Pits", {                                    # 第一次见坑，还被 D 追着
		"gaps": [(160, 96), (420, 96), (680, 96)],
		"ledges": [(540, 248, 96)],
		"enemies": [("chaser_d", 880, GROUND_Y), ("walker_a", 1080, GROUND_Y)],
	}),
	("Breather", {                                # 喘口气（以后检查点放这儿）
		"ledges": [(180, 256, 128), (400, 208, 96)],
		"enemies": [("walker_a", 980, GROUND_Y)],
	}),
	("Grenadier", {                               # F 在高台扔手雷，地面有掩体墙
		"ledges": [(240, 264, 96), (400, 216, 128)],
		"walls": [(120, 56), (600, 56)],
		"enemies": [("walker_f", 450, 216), ("walker_a", 900, GROUND_Y),
			("turret", 1150, GROUND_Y), ("walker_a", 1240, GROUND_Y)],
	}),
	("Skies", {                                   # 坑上空两个 E：一边跳一边朝上打
		"gaps": [(220, 128), (520, 96)],
		"ledges": [(272, 272, 48), (760, 248, 96)],
		"enemies": [("flyer_e", 320, None), ("flyer_e", 820, None),
			("walker_c", 1120, GROUND_Y)],
	}),
	("Crossfire", {                               # 上下两层，综合压力
		"ledges": [(140, 248, 160), (400, 200, 160), (940, 248, 128)],
		"enemies": [("walker_b", 200, 248), ("turret", 480, 200),
			("walker_a", 700, GROUND_Y), ("walker_c", 1140, GROUND_Y),
			("walker_f", 980, 248)],
	}),
	("Sprint", {                                  # 窄道 + 两个 D：体力真正有用的地方
		"crawl": [(160, 160)],
		"gaps": [(560, 96), (810, 96)],
		"walls": [(1160, 40)],
		"enemies": [("chaser_d", 420, GROUND_Y), ("chaser_d", 1010, GROUND_Y),
			("walker_a", 1240, GROUND_Y)],
	}),
	("BossArena", {                               # 收尾：一道墙围出来的平地
		"walls": [(40, 56)],
		"ledges": [(480, 248, 112)],
		"enemies": [("boss_a", 880, GROUND_Y)],
	}),
]


## 玩家出生点。
SPAWN = (64.0, GROUND_Y - STAND)


# ---------------------------------------------------------------- 摊平成一整关

class Level:
	def __init__(self):
		self.width = SECTION * len(SECTIONS)
		self.gaps = []        # (x, 宽)
		self.ledges = []      # (名字, x, 顶边 y, 宽)
		self.walls = []       # (名字, x, 高)
		self.crawls = []      # (名字, x, 宽)
		self.enemies = []     # (名字, 类型, x, y)
		self.ground = []      # (x, 宽)
		self._build()

	def _build(self):
		counts = {}

		def name(kind):
			counts[kind] = counts.get(kind, 0) + 1
			return "%s%d" % (kind, counts[kind])

		for index, (label, parts) in enumerate(SECTIONS):
			base = index * SECTION
			for x, wide in parts.get("gaps", []):
				self.gaps.append((base + x, wide))
			for x, top, wide in parts.get("ledges", []):
				self.ledges.append((name("Ledge"), base + x, top, wide))
			for x, high in parts.get("walls", []):
				self.walls.append((name("Wall"), base + x, high))
			for x, wide in parts.get("crawl", []):
				self.crawls.append((name("Crawl"), base + x, wide))
			for kind, x, surface in parts.get("enemies", []):
				y = FLY_Y if surface is None else surface - (BOSS_STAND if kind == "boss_a" else STAND)
				self.enemies.append((label + kind.title().replace("_", ""), kind, base + x, y))
		self.ground = self._ground_runs()

	def _ground_runs(self):
		"""地面 = 整条减去坑，切成一段一段。"""
		runs, at = [], 0.0
		for x, wide in sorted(self.gaps):
			if x > at:
				runs.append((at, x - at))
			at = x + wide
		if at < self.width:
			runs.append((at, self.width - at))
		return runs

	def surfaces(self):
		"""能站人的面：(左, 右, 顶边 y)。地面按段算，浮台各算一块。"""
		out = [(x, x + wide, GROUND_Y) for x, wide in self.ground]
		out += [(x, x + wide, top) for _, x, top, wide in self.ledges]
		return out

	def surface_at(self, x):
		"""这个 x 站得住吗（在地面上还是悬空）。"""
		for left, right, top in self.surfaces():
			if left <= x <= right and top == GROUND_Y:
				return top
		return None


# ---------------------------------------------------------------- 自检

def check_level(level):
	"""跑得通吗。**数字不对就报错**，不产出一个过不去的关卡。"""
	problems = []
	for x, wide in level.gaps:
		# 坑里架了浮台就一跳一跳地算：从左岸跳上浮台、再从浮台跳到右岸
		steps = [x]
		for _, lx, top, lwide in level.ledges:
			if lx >= x and lx + lwide <= x + wide:
				if GROUND_Y - top > MAX_GAP / 2.0:
					problems.append("坑 %.0f 里的浮台架得太高（%.0f），跳上去就没横向距离了"
						% (x, GROUND_Y - top))
				steps += [lx, lx + lwide]
		steps.append(x + wide)
		steps.sort()
		for i in range(0, len(steps) - 1, 2):
			hop = steps[i + 1] - steps[i]
			if hop > MAX_GAP:
				problems.append("坑 %.0f 有一跳是 %.0f，走着跳最多 %.0f" % (x, hop, MAX_GAP))
	for name, x, high in level.walls:
		if high > MAX_WALL:
			problems.append("%s 高 %.0f，跳不过去（最多 %.0f）" % (name, high, MAX_WALL))
		if level.surface_at(x) is None:
			problems.append("%s 架在坑上" % name)
	for name, x, wide in level.crawls:
		if level.surface_at(x) is None or level.surface_at(x + wide) is None:
			problems.append("%s 架在坑上" % name)
	# 浮台要够得着：横着差 120 以内、底下有个面，落差不超过一次跳
	for name, x, top, wide in level.ledges:
		best = None
		for left, right, other in level.surfaces():
			if other <= top:
				continue
			if right < x - 120.0 or left > x + wide + 120.0:
				continue
			step = other - top
			best = step if best is None else min(best, step)
		if best is None:
			problems.append("%s 底下没有能起跳的地方" % name)
		elif best > MAX_STEP:
			problems.append("%s 比底下的面高 %.0f，一次跳最多 %.0f" % (name, best, MAX_STEP))
	# 敌人：站在地上的不能悬空，也不能塞进矮通道（它们 32 高，净空只有 30，会卡死不动）
	for name, kind, x, y in level.enemies:
		if kind == "flyer_e":
			continue
		feet = y + (BOSS_STAND if kind == "boss_a" else STAND)
		on_ledge = any(left - 8 <= x <= right + 8 and abs(top - feet) < 1.0
			for left, right, top in level.surfaces())
		if not on_ledge:
			problems.append("%s 站在 (%.0f, %.0f)，脚下没有面" % (name, x, y))
		if abs(feet - GROUND_Y) < 1.0:
			for _, cx, cwide in level.crawls:
				if cx - 24 <= x <= cx + cwide + 24:
					problems.append("%s 摆在矮通道底下，会被卡住不动" % name)
	return problems


# ---------------------------------------------------------------- 写场景

HEAD = """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://scenes/platform.tscn" id="1"]
[ext_resource type="PackedScene" path="res://scenes/player.tscn" id="2"]
[ext_resource type="Script" path="res://scripts/main.gd" id="3"]
[ext_resource type="PackedScene" path="res://scenes/hud.tscn" id="6"]
[ext_resource type="Script" path="res://scripts/fx.gd" id="13"]
[ext_resource type="PackedScene" path="res://scenes/muzzle_flash.tscn" id="14"]
[ext_resource type="PackedScene" path="res://scenes/hit_spark.tscn" id="15"]
[ext_resource type="PackedScene" path="res://scenes/impact_spark.tscn" id="16"]
[ext_resource type="Script" path="res://scripts/camera_rig.gd" id="17"]
[ext_resource type="PackedScene" path="res://scenes/explosion.tscn" id="18"]
[ext_resource type="PackedScene" path="res://scenes/ui/pause_menu.tscn" id="19"]
[ext_resource type="PackedScene" path="res://scenes/ui/death_screen.tscn" id="20"]
"""


def platform(name, parent, x, y, w, h, one_way=False, skin=None):
	lines = ['[node name="%s" parent="%s" instance=ExtResource("1")]' % (name, parent)]
	if skin:
		lines.append('skin_key = &"%s"' % skin)
	lines.append("position = Vector2(%g, %g)" % (x, y))
	lines.append("size = Vector2(%g, %g)" % (w, h))
	if one_way:
		lines.append("one_way = true")
	return "\n".join(lines) + "\n"


def build(level, write):
	ids = {}
	extra = []
	for index, kind in enumerate(sorted({e[1] for e in level.enemies})):
		ids[kind] = "e%d" % index
		extra.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (ENEMIES[kind], ids[kind]))

	out = [HEAD + "\n".join(extra) + "\n"]
	out.append('\n[node name="Level1" type="Node2D"]\nscript = ExtResource("3")\n')
	out.append('\n[node name="Level" type="Node2D" parent="."]\n')
	for index, (x, wide) in enumerate(level.ground):
		out.append("\n" + platform("Ground%d" % (index + 1), "Level", x, GROUND_Y, wide,
			GROUND_THICK, skin="terrain_ground"))
	out.append("\n" + platform("WallLeft", "Level", -16, 0, 16, SCREEN_H))
	out.append("\n" + platform("WallRight", "Level", level.width, 0, 16, SCREEN_H))
	for name, x, top, wide in level.ledges:
		out.append("\n" + platform(name, "Level", x, top, wide, 16, one_way=True))
	for name, x, wide in level.crawls:
		top = GROUND_Y - CRAWL_CLEAR - CRAWL_THICK
		out.append("\n" + platform(name, "Level", x, top, wide, CRAWL_THICK))
	out.append('\n[node name="Walls" type="Node2D" parent="Level"]\n')
	for name, x, high in level.walls:
		out.append("\n" + platform(name, "Level/Walls", x, GROUND_Y - high, 16, high))

	out.append('\n[node name="Enemies" type="Node2D" parent="."]\n')
	for name, kind, x, y in level.enemies:
		out.append('\n[node name="%s" parent="Enemies" instance=ExtResource("%s")]\n'
			'position = Vector2(%g, %g)\n' % (name, ids[kind], x, y))

	out.append('\n[node name="Fx" type="Node2D" parent="."]\n'
		'script = ExtResource("13")\n'
		'muzzle_flash_scene = ExtResource("14")\n'
		'hit_spark_scene = ExtResource("15")\n'
		'impact_spark_scene = ExtResource("16")\n'
		'explosion_scene = ExtResource("18")\n')
	out.append('\n[node name="Player" parent="." instance=ExtResource("2")]\n'
		'position = Vector2(%g, %g)\n' % SPAWN)
	out.append('\n[node name="Camera2D" type="Camera2D" parent="."]\n'
		'position = Vector2(%g, %g)\n'
		'script = ExtResource("17")\n'
		'limit_left = 0\nlimit_top = 0\nlimit_right = %d\nlimit_bottom = %d\n'
		% (SPAWN[0], SPAWN[1] - 8, level.width, SCREEN_H))
	out.append('\n[node name="HUD" parent="." instance=ExtResource("6")]\n')
	out.append('\n[node name="PauseMenu" parent="." instance=ExtResource("19")]\n')
	out.append('\n[node name="DeathScreen" parent="." instance=ExtResource("20")]\n')

	if write:
		with open(OUT, "w", newline="\n", encoding="utf-8") as f:
			f.write("".join(out))
	return "".join(out)


def main():
	write = "--check" not in sys.argv
	level = Level()
	problems = check_level(level)
	if problems:
		print("关卡自检没过：")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	build(level, write)
	print("第一关：%d 宽（%d 段 / %d 屏）" % (level.width, len(SECTIONS), level.width // 640))
	print("  地面 %d 段、坑 %d 个（最宽 %.0f，走着跳的上限 %.0f）"
		% (len(level.ground), len(level.gaps),
			max([w for _, w in level.gaps] or [0]), MAX_GAP))
	print("  浮台 %d、竖墙 %d、矮通道 %d" % (len(level.ledges), len(level.walls), len(level.crawls)))
	kinds = {}
	for _, kind, _, _ in level.enemies:
		kinds[kind] = kinds.get(kind, 0) + 1
	print("  敌人 %d 个：%s" % (len(level.enemies),
		"、".join("%s×%d" % (k, n) for k, n in sorted(kinds.items()))))
	if write:
		print("  写入 scenes/level_1.tscn")


if __name__ == "__main__":
	main()
