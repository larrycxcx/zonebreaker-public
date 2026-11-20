"""生成正式关卡场景（scenes/level_N.tscn）。

    python tools/level_build.py          # 全部关卡
    python tools/level_build.py 2        # 只生成第二关
    python tools/level_build.py demo     # 用户示意图那一屏（scenes/map_demo.tscn）
    python tools/level_build.py --check  # 只自检，不写文件

**为什么用脚本生成**：正式关卡 12800 宽 = 20 屏，手写几百个节点没法迭代——
调一下节奏就要重排一整屏。和 `skin_build.py` 那套是一个路子：规则和数字写在脚本里，产物进仓库。

**两种关卡**（2026-10 起）：
**全部四关都是格子地图**：`level1_map.py` … `level4_map.py` 画，`map_build.py` 找路自检、挑砖、写场景
（见 CLAUDE.md「梯子与分层关卡」）。第四关是**竖着的**一整根竖井（40 × 450 格）。
原来那两套生成器（横向的「段落表」、纵向的 `vlevel_build.py`）都随着关卡换成格子地图删掉了。

这里只剩：几把公用的尺子、每关的敌人表、`STAGES` 那张总表、写场景用的文件头和平台节点。
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
SCENES = os.path.join(HERE, "..", "scenes")

# ---------------------------------------------------------------- 公用的尺子

## 地面顶边的 y。
GROUND_Y = 320.0
## 画面多高。摄像机的 limit_bottom 用它。
SCREEN_H = 360.0
## 站在地上的敌人 / 玩家的 y：判定框 32 高、原点在正中，所以是地面顶边往上 16。
STAND = 16.0
## Boss A 的判定框 48 高，原点在正中 → 顶边往上 24。
BOSS_STAND = 24.0

## 从天而降的 2-A 吊在画面顶边以上的这个高度，玩家走到脚下才砸下来。
HANG_Y = -40.0

## 机关的场景（第二关的液压机和闸门）。
PRESS_SCENE = "res://scenes/trap_press.tscn"
GATE_SCENE = "res://scenes/trap_gate.tscn"

## 敌人在关卡里叫什么：键 `1_a` → `1-A`、`1_boss` → `1-Boss`。
## **编号带着关卡号**：23 关每关都有自己的一套敌人，字母只是这一关的序号（不代表打法），
## 所以第二关的就是 `2-A`、`2-B`……字母不带关卡号的话很快就不够分了。
def enemy_label(kind):
	level, _, rest = kind.partition("_")
	return "%s-%s" % (level, "Boss" if rest == "boss" else rest.upper())


## 敌人类型 → 场景路径。键就是地图 / 段落表里写的名字。
ENEMIES_1 = {
	"1_a": "res://scenes/enemy_1_a.tscn",
	"1_b": "res://scenes/enemy_1_b.tscn",
	"1_c": "res://scenes/enemy_1_c.tscn",
	"1_f": "res://scenes/enemy_1_f.tscn",
	"1_g": "res://scenes/enemy_1_g.tscn",
	"1_d": "res://scenes/enemy_1_d.tscn",
	"1_e": "res://scenes/enemy_1_e.tscn",
	"1_boss": "res://scenes/boss_1.tscn",
}

## 装饰物：名字 → 横着排了几帧（1 = 静止）。**纯显示，没有碰撞**（`scripts/prop.gd`）。
PROP_FRAMES_1 = {"fountain": 4}


# ---------------------------------------------------------------- 第二关（工业区）
#
# 分层的格子地图（`level2_map.py`），这里只留它的敌人表和会动的装饰。

PROP_FRAMES_2 = {"screen": 4, "conveyor": 4}

ENEMIES_2 = {
	"2_a": "res://scenes/enemy_2_a.tscn",
	"2_b": "res://scenes/enemy_2_b.tscn",
	"2_c": "res://scenes/enemy_2_c.tscn",
	"2_d": "res://scenes/enemy_2_d.tscn",
	"2_e": "res://scenes/enemy_2_e.tscn",
	"2_f": "res://scenes/enemy_2_f.tscn",
	"2_boss": "res://scenes/boss_2.tscn",
}


# ---------------------------------------------------------------- 第三关（酒吧街）
#
# 分层的格子地图（`level3_map.py`）。这一关**没有会飞的**，也**没有会动的装饰**：
# 酒瓶、酒杯、飞钞、飘牌摆在地上像能捡的东西（2026-10 试玩反馈），都不要。

PROP_FRAMES_3 = {}

ENEMIES_3 = {
	"3_a": "res://scenes/enemy_3_a.tscn",
	"3_b": "res://scenes/enemy_3_b.tscn",
	"3_c": "res://scenes/enemy_3_c.tscn",
	"3_d": "res://scenes/enemy_3_d.tscn",
	"3_e": "res://scenes/enemy_3_e.tscn",
	"3_f": "res://scenes/enemy_3_f.tscn",
	"3_boss": "res://scenes/boss_3.tscn",
}

## 脚底在原点下方几像素，**和别人不一样的**才写：3-E 趴在地上只有 12 高（判定框 28×12），
## 独轮机甲的判定框 56 高。按 `STAND` / `BOSS_STAND` 摆的话一个陷进地里、一个悬在半空。
STAND_3 = {"3_e": 6.0, "3_boss": 28.0}

SECTIONS_3 = [
	("Sidewalk", {                                # 街口：认识 3-B，第一次见贴地的 3-E
		"props": [("counter", 300, GROUND_Y), ("sign2", 620, GROUND_Y),
			("counter2", 940, GROUND_Y)],
		"ledges": [(260, 256, 96), (420, 208, 96), (640, 256, 112), (860, 208, 96),
			(1060, 248, 96)],
		"enemies": [("3_b", 840, GROUND_Y), ("3_a", 960, GROUND_Y), ("3_b", 880, 208),
			("3_e", 1020, GROUND_Y), ("3_b", 1100, 248), ("3_a", 1220, GROUND_Y)],
	}),
	("Awnings", {                                 # 踩着雨棚往上爬，跳劈的 3-C 从上面扑下来
		"ledges": [(100, 264, 96), (260, 216, 96), (420, 168, 128), (620, 160, 240),
			(900, 216, 96), (1080, 256, 112)],
		"walls": [(180, 40)],
		"gaps": [(1000, 88)],
		"blocks": [(660, 64, 112)],
		"enemies": [("3_b", 150, GROUND_Y), ("3_c", 300, 216), ("3_b", 480, 168),
			("3_d", 560, GROUND_Y), ("3_c", 700, 160), ("3_e", 780, GROUND_Y),
			("3_b", 820, 160), ("3_b", 950, 216), ("3_b", 1140, 256),
			("3_a", 1150, GROUND_Y)],
	}),
	("Cellar", {                                  # 矮通道 + 堵死的下层：出口站着壮汉
		"crawl": [(200, 200), (800, 180)],
		"blocks": [(520, 64, 112)],
		"ledges": [(340, 248, 80), (400, 208, 64), (440, 160, 240), (720, 248, 96),
			(1000, 200, 96), (1160, 256, 96)],
		"enemies": [("3_d", 460, GROUND_Y), ("3_b", 500, 160), ("3_e", 700, GROUND_Y),
			("3_b", 760, 248), ("3_d", 1040, GROUND_Y), ("3_c", 1040, 200),
			("3_a", 1200, GROUND_Y), ("3_b", 1200, 256)],
	}),
	("Gutters", {                                 # 坑区：3-E 守着坑边，要跳过它的子弹又要跳过坑
		"gaps": [(300, 96), (620, 88), (940, 100)],
		"ledges": [(180, 248, 96), (460, 264, 96), (760, 248, 112), (1080, 256, 96)],
		"enemies": [("3_b", 200, 248), ("3_e", 500, GROUND_Y), ("3_c", 500, 264),
			("3_d", 800, GROUND_Y), ("3_b", 800, 248), ("3_e", 880, GROUND_Y),
			("3_f", 1060, GROUND_Y), ("3_b", 1120, 256), ("3_a", 1240, GROUND_Y)],
	}),
	("Bouncers", {                                # 壮汉的地盘：正面打不动，得绕
		"props": [("counter2", 400, GROUND_Y), ("sign2", 1000, GROUND_Y)],
		"ledges": [(220, 256, 96), (460, 256, 80), (560, 208, 112), (900, 256, 96),
			(1020, 256, 80), (1120, 208, 96)],
		"walls": [(740, 56)],
		"enemies": [("3_d", 180, GROUND_Y), ("3_b", 260, 256), ("3_a", 620, GROUND_Y),
			("3_b", 600, 208), ("3_d", 860, GROUND_Y), ("3_b", 940, 256),
			("3_f", 1060, GROUND_Y), ("3_d", 1180, GROUND_Y), ("3_c", 1160, 208)],
	}),
	("Carts", {                                   # 长直路上的炮车，上面一条高路
		"props": [("cabinet", 300, GROUND_Y)],
		"ledges": [(160, 256, 96), (340, 208, 96), (480, 160, 256), (820, 256, 96),
			(980, 208, 96), (1140, 256, 96)],
		"blocks": [(560, 64, 120)],
		"walls": [(1080, 48)],
		"enemies": [("3_f", 260, GROUND_Y), ("3_b", 380, 208), ("3_f", 420, GROUND_Y),
			("3_b", 520, 160), ("3_b", 700, 160), ("3_f", 760, GROUND_Y),
			("3_e", 900, GROUND_Y), ("3_c", 1020, 208), ("3_b", 1160, 256),
			("3_f", 1200, GROUND_Y)],
	}),
	("Rooftops", {                                # 一路踩雨棚过坑，3-C 在棚子之间跳来跳去
		"gaps": [(360, 92), (820, 96)],
		"ledges": [(180, 264, 96), (320, 216, 112), (520, 264, 96), (700, 216, 112),
			(900, 264, 96), (1080, 216, 112)],
		"enemies": [("3_b", 200, 264), ("3_c", 360, 216), ("3_b", 560, 264),
			("3_e", 640, GROUND_Y), ("3_c", 740, 216), ("3_b", 940, 264),
			("3_a", 1000, GROUND_Y), ("3_c", 1120, 216), ("3_b", 1200, GROUND_Y)],
	}),
	("Crossfire", {                               # 三层交叉火力，底下还有一条贴地的
		"ledges": [(120, 264, 128), (340, 208, 128), (560, 152, 160), (820, 208, 128),
			(1040, 264, 128)],
		"gaps": [(700, 92)],
		"enemies": [("3_b", 160, 264), ("3_f", 260, GROUND_Y), ("3_b", 380, 208),
			("3_b", 600, 152), ("3_e", 640, GROUND_Y), ("3_b", 660, 152),
			("3_b", 860, 208), ("3_d", 980, GROUND_Y), ("3_b", 1080, 264),
			("3_a", 1200, GROUND_Y)],
	}),
	("BackAlley", {                               # 后巷：坑、矮通道、壮汉和刀客挤在一起
		"crawl": [(160, 180), (660, 160)],
		"gaps": [(420, 96), (900, 100), (1090, 92)],
		"ledges": [(320, 248, 96), (520, 184, 96), (840, 248, 64), (1020, 248, 64)],
		"walls": [(1220, 40)],
		"blocks": [(540, 56, 112)],
		"enemies": [("3_d", 380, GROUND_Y), ("3_b", 360, 248), ("3_a", 620, GROUND_Y),
			("3_b", 560, 184), ("3_b", 860, 248), ("3_e", 870, GROUND_Y),
			("3_d", 1040, GROUND_Y), ("3_c", 1040, 248), ("3_b", 1250, GROUND_Y)],
	}),
	("BossArena", {                               # Boss 区：**整片实地、没有墙**，它在地上滚
		"props": [("counter", 260, GROUND_Y), ("cabinet2", 640, GROUND_Y)],
		"walls": [(40, 56)],
		"ledges": [(180, 248, 96), (360, 200, 96), (560, 248, 112),
			(820, 256, 96), (1120, 248, 96)],
		"enemies": [("3_d", 140, GROUND_Y), ("3_b", 220, 248), ("3_f", 420, GROUND_Y),
			("3_b", 400, 200), ("3_a", 620, GROUND_Y), ("3_b", 600, 248),
			("3_boss", 1000, GROUND_Y)],
	}),
]

# ---------------------------------------------------------------- 第四关（地下室，纵向往上爬）
#
# 竖着的格子地图（`level4_map.py`），这里只留它的敌人表、矮的那种站多高、会动的装饰。

ENEMIES_4 = {
	"4_a": "res://scenes/enemy_4_a.tscn",
	"4_b": "res://scenes/enemy_4_b.tscn",
	"4_c": "res://scenes/enemy_4_c.tscn",
	"4_d": "res://scenes/enemy_4_d.tscn",
	"4_e": "res://scenes/enemy_4_e.tscn",
	"4_f": "res://scenes/enemy_4_f.tscn",
	"4_boss": "res://scenes/boss_4.tscn",
}
## 蜘蛛炮台矮（判定框 22 高），脚底在原点下方 11。
STAND_4 = {"4_e": 11.0}
PROP_FRAMES_4 = {"smoke": 6}

# ---------------------------------------------------------------- 第五关（实验室）
#
# 分层的格子地图（`level5_map.py`）。中段有一间小 Boss 的房间（门 `[` `]`，见 `ArenaDoor`）。

ENEMIES_5 = {
	"5_a": "res://scenes/enemy_5_a.tscn",
	"5_b": "res://scenes/enemy_5_b.tscn",
	"5_c": "res://scenes/enemy_5_c.tscn",
	"5_d": "res://scenes/enemy_5_d.tscn",
	"5_e": "res://scenes/enemy_5_e.tscn",
	"5_f": "res://scenes/enemy_5_f.tscn",
	"5_mid": "res://scenes/boss_5_mid.tscn",
	"5_boss": "res://scenes/boss_5.tscn",
}
## 变异枪手的判定框 48 高，脚底在原点下方 24（它的名字不以 _boss 结尾，得点名）。
STAND_5 = {"5_mid": 24.0}
PROP_FRAMES_5 = {"generator": 4, "valve": 4, "scanner": 6, "camera": 6}

# ---------------------------------------------------------------- 一关 = 一条配置
#
# 加一关就往这张表里加一条，跑 `python tools/level_build.py 2`。
# 关卡之间**什么都不共用**：敌人、装饰、地图各写各的——23 关里每一关的敌人和素材都不一样，
# 共用一份只会让「调第二关的节奏」把第一关也改掉。
STAGES = {
	# 全部是**格子地图**：`levelN_map.py` 画、`map_build.py` 查路和写场景，
	# `theme` 是那个区的一套砖（`map_build.THEMES`）
	"1": {
		"out": "level_1.tscn", "root": "Level1", "prop_dir": "cyberpunk", "map": "level1_map",
		"theme": "green", "enemies": ENEMIES_1, "prop_frames": PROP_FRAMES_1,
	},
	"2": {
		"out": "level_2.tscn", "root": "Level2", "prop_dir": "industrial", "map": "level2_map",
		"theme": "industrial",
		"enemies": ENEMIES_2, "prop_frames": PROP_FRAMES_2,
	},
	"3": {
		"out": "level_3.tscn", "root": "Level3", "prop_dir": "bar_street", "map": "level3_map",
		"theme": "bar", "enemies": ENEMIES_3, "prop_frames": PROP_FRAMES_3, "stand": STAND_3,
	},
	# 第四关是**竖着的**格子地图（2026-10 从原来那套纵向段落表换过来）：一整根竖井，450 行高
	"4": {
		"out": "level_4.tscn", "root": "Level4", "prop_dir": "basement", "map": "level4_map",
		"theme": "basement", "enemies": ENEMIES_4, "prop_frames": PROP_FRAMES_4, "stand": STAND_4,
	},
	"5": {
		"out": "level_5.tscn", "root": "Level5", "prop_dir": "lab", "map": "level5_map",
		"theme": "lab", "enemies": ENEMIES_5, "prop_frames": PROP_FRAMES_5, "stand": STAND_5,
	},
}


def use_stage(key):
	"""把这一关「哪种敌人脚底离原点多远」那张表装进全局（`stand_of()` 读它）。"""
	global STAND_BY
	STAND_BY = STAGES[key].get("stand", {})


STAND_BY = {}


def stand_of(kind):
	"""脚底在原点下方几像素：表里点了名的按表，否则 Boss 24、别人 16。"""
	if kind in STAND_BY:
		return STAND_BY[kind]
	return BOSS_STAND if kind.endswith("_boss") else STAND


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
[ext_resource type="PackedScene" path="res://scenes/ui/clear_screen.tscn" id="22"]
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


def build_map_demo(write):
	"""用户示意图那一屏（`level_maps.DEMO`），生成到 scenes/map_demo.tscn，不进选关列表。"""
	import level_maps
	import map_build as mb
	level = mb.MapLevel(level_maps.DEMO, level_maps.DEMO_ENEMIES, ENEMIES_2, lambda kind: STAND)
	problems = mb.check(level, safe_cols=0)   # 示意图那一屏本来就只有一屏，敌人都在里面
	if problems:
		print("格子地图自检没过：")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	mb.build(level, os.path.join(SCENES, "map_demo.tscn"), "MapDemo", "industrial", write,
		PROP_FRAMES_2, level_maps.DEMO_PROPS, level_maps.DEMO_DECOR)
	print("示意图那一段：%d 格宽（%d 像素）" % (level.width, level.width * mb.CELL))
	print("  实心 %d 块、单向 %d、梯子 %d、液压机 %d、闸门 %d、敌人 %d"
		% (len(level.solids), len(level.ledges), len(level.ladders), len(level.presses),
			len(level.gates), len(level.enemies)))
	if write:
		print("  写入 scenes/map_demo.tscn")


def build_map_level(key, write):
	"""分层的格子地图（第一关 `level1_map.py`、第二关 `level2_map.py`）→ scenes/level_N.tscn。"""
	import importlib
	import map_build as mb
	import map_canvas
	stage = STAGES[key]
	plan = importlib.import_module(stage["map"])
	mb.use_theme(stage["theme"])
	rows, props, decor = plan.assemble()
	level = mb.MapLevel(rows, plan.LETTERS, stage["enemies"], stand_of, plan.FLOATING, plan.HANGING,
		getattr(plan, "FLOAT_AT", None))
	problems = mb.check(level, chasers=plan.CHASERS, min_enemies=plan.MIN_ENEMIES)
	if problems:
		map_canvas.dump(rows)
		print("格子地图自检没过：")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	mb.build(level, os.path.join(SCENES, stage["out"]), stage["root"], stage["prop_dir"], write,
		stage["prop_frames"], props, decor)
	if level.vertical:
		print("第 %s 关（纵向）：%d × %d 格（%d 屏高）" % (key, level.width, level.height, level.height * 16 // 360))
	else:
		print("第 %s 关（分层）：%d 格宽（%d 屏）" % (key, level.width, level.width // 40))
	print("  实心 %d 块、单向 %d、梯子 %d、液压机 %d、闸门 %d、箱子 %d、油桶 %d、敌人 %d、装饰 %d"
		% (len(level.solids), len(level.ledges), len(level.ladders), len(level.presses),
			len(level.gates), len(level.crates), len(level.barrels), len(level.enemies), len(level.props)))
	if write:
		print("  写入 scenes/%s" % stage["out"])


def main():
	write = "--check" not in sys.argv
	if "demo" in sys.argv:
		build_map_demo(write)
		return
	wanted = [a for a in sys.argv[1:] if not a.startswith("--")] or list(STAGES)
	for key in wanted:
		if key not in STAGES:
			sys.exit("没有第 %s 关（有的是 %s）" % (key, "、".join(STAGES)))
		use_stage(key)
		build_stage(key, write)


def build_stage(key, write):
	if not STAGES[key].get("map"):
		sys.exit("第 %s 关没有配格子地图" % key)
	build_map_level(key, write)


if __name__ == "__main__":
	main()
