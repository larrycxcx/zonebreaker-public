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
SCENES = os.path.join(HERE, "..", "scenes")

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
## 「堵死」用的实心方块最矮多少：比一次跳跃还高，底下那条路就断了，必须从上面的浮台绕过去。
MIN_BLOCK = JUMP_HEIGHT + 16.0             # 103
## 浮台要盖在堵块顶上多少，人站上去才不会嵌进方块里。
BLOCK_CLEAR = 16.0
## 矮通道净空：站着 32 过不去、站姿子弹 25 过得去，窗口只有几个像素（见 CLAUDE.md）。
CRAWL_CLEAR = 30.0
## 矮通道那块砖画多厚。
CRAWL_THICK = 50.0
## 摆在半空里：段落表里第三个值写 `("air", y)` 就是「原点直接放在这个 y」，
## 给的是**绝对高度**，不是脚下那个面。两种用法：
## 从天而降的 2-A 吊在画面顶边以上（`HANG_Y`），以及飘在空中的 Boss。
AIR = "air"
HANG_Y = -40.0

## 出生点往后多远之内不许摆敌人。
## **人一进来就在挨打，连看清楚周围都来不及**（2026-09 试玩发现）。
## 摄像机一开始夹在关卡左边，画面就是 x 0..640，而敌人**只要有一部分在画面里就算够得着**
## （见 CLAUDE.md 的「视野对等」），所以第一个敌人得在画面外，再留一点余量。
SAFE_START = 700.0

## 装饰物：名字 → 横着排了几帧（1 = 静止）。贴图在 `skins/cyberpunk/props/`，
## 由 `tools/terrain_build.py` 从地形素材包里挑出来。**纯显示，没有碰撞**，
## 画在所有东西后面，再密也不挡敌人和子弹（`scripts/prop.gd`）。
PROP_FRAMES_1 = {"fountain": 4}
## 沿着地面随手撒的小东西。
SCATTER_1 = ["grass_tuft", "grass_blade", "grass_tuft", "rock_small", "bush_flat",
	"bush_wide", "rock", "bin", "box", "bush_big", "grass_blade"]
## 隔一段撒一棵树。
TREES_1 = ["tree_small", "tree_big", "tree_small"]
## 撒的间隔（像素）：小东西密一点，树疏一点。
SCATTER_STEP = (40, 130)
TREE_STEP = (240, 460)
## 撒的随机种子。**固定**：产物是要进仓库的，重新生成必须一模一样。
SCATTER_SEED_1 = 20260924

## 敌人在关卡里叫什么：键 `1_a` → `1-A`、`1_boss` → `1-Boss`。
## **编号带着关卡号**：23 关每关都有自己的一套敌人，字母只是这一关的序号（不代表打法），
## 所以第二关的就是 `2-A`、`2-B`……字母不带关卡号的话很快就不够分了。
def enemy_label(kind):
	level, _, rest = kind.partition("_")
	return "%s-%s" % (level, "Boss" if rest == "boss" else rest.upper())


## 敌人类型 → 场景路径。键就是 `SECTIONS` 里写的名字。
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

FLYING_1 = {"1_e"}

# ---------------------------------------------------------------- 第一关的段落
#
# 每段：(名字, {
#   "gaps":   [(段内 x, 宽)]            地面在这儿断开 —— 掉下去就死
#   "ledges": [(段内 x, 顶边 y, 宽)]     单向浮台，从下面能穿上去
#   "walls":  [(段内 x, 高)]            实心竖墙，挡路挡子弹，巡逻兵碰到掉头
#   "blocks": [(段内 x, 宽, 高)]         **把下面那条路堵死**的实心方块：比一次跳跃还高，
#                                        必须踩着上面的浮台绕过去（生成时会检查真有那条高路）
#   "crawl":  [(段内 x, 宽)]            矮通道顶块，底下只剩 30px，必须趴着爬
#   "enemies":[(类型, 段内 x, 站在哪个顶边上)]
#   "props":  [(装饰名, 段内 x, 站在哪个顶边上)]   摆在固定位置的大件（喷泉、长椅、栅栏）；
#                                        小草小石头由 `scatter()` 沿着地面自动撒
# })
#
# 「站在哪个顶边上」写的是**脚下那个面的 y**（地面就是 GROUND_Y，浮台就是它的顶边），
# 生成时自动换算成敌人的原点高度；飞行的 E 写 None。

SECTIONS_1 = [
	("Warmup", {                                  # 唯一一段让你站稳脚跟的地方
		# **头一屏空着**（见 `SAFE_START`）：让人走两步、试试手感，再碰上第一个敌人
		"props": [("fountain", 300, GROUND_Y), ("bench", 560, GROUND_Y),
			("bench2", 1180, GROUND_Y)],
		"ledges": [(260, 256, 96), (420, 208, 96), (640, 256, 112), (860, 200, 96),
			(1060, 248, 96)],
		"enemies": [("1_a", 720, 256), ("1_a", 780, GROUND_Y),
			("1_g", 900, 200), ("1_a", 1000, GROUND_Y),
			("1_b", 1100, 248), ("1_a", 1240, GROUND_Y)],
	}),
	("Stairs", {                                  # 爬上去，顺便认识第一块「下面走不通」
		"ledges": [(100, 264, 96), (260, 216, 96), (420, 168, 128), (620, 160, 240),
			(900, 248, 96)],
		"blocks": [(700, 64, 112)],
		"walls": [(180, 40)],
		"enemies": [("1_a", 150, GROUND_Y), ("1_b", 300, 216),
			("1_g", 480, 168), ("1_a", 660, GROUND_Y), ("1_c", 700, 160),
			("1_g", 820, 160), ("1_a", 950, 248), ("1_a", 1100, GROUND_Y),
			("1_d", 1220, GROUND_Y)],
	}),
	("Crawl", {                                   # 两道矮通道，出口都有炮台等着
		"crawl": [(180, 220), (760, 180)],
		"ledges": [(460, 248, 112), (620, 200, 96), (980, 248, 112), (1140, 200, 96)],
		"enemies": [("1_g", 430, GROUND_Y), ("1_e", 300, None),
			("1_a", 520, 248), ("1_b", 660, 200), ("1_a", 700, GROUND_Y),
			("1_g", 1000, GROUND_Y), ("1_c", 1020, 248), ("1_e", 900, None),
			("1_a", 1240, GROUND_Y)],
	}),
	("Pits", {                                    # 四个坑，最后一个宽到要踩中间那块小台
		"gaps": [(120, 96), (330, 100), (520, 96), (760, 160)],
		"ledges": [(230, 248, 96), (440, 208, 80), (800, 272, 72), (960, 248, 128),
			(1140, 200, 96)],
		"enemies": [("1_d", 60, GROUND_Y), ("1_a", 280, 248),
			("1_g", 470, 208), ("1_e", 600, None), ("1_a", 660, GROUND_Y),
			("1_d", 1000, GROUND_Y), ("1_b", 1000, 248),
			("1_a", 1180, 200), ("1_a", 1250, GROUND_Y)],
	}),
	("Fortress", {                                # 一整片高台，底下被堵死
		"props": [("fountain", 860, GROUND_Y), ("fence", 200, GROUND_Y),
			("bench", 1000, GROUND_Y)],
		"ledges": [(140, 264, 96), (280, 248, 96), (420, 176, 280), (760, 248, 96),
			(920, 184, 96), (1100, 248, 112)],
		"blocks": [(520, 64, 120)],
		"enemies": [("1_a", 100, GROUND_Y), ("1_b", 320, 248),
			("1_g", 500, 176), ("1_c", 620, 176), ("1_a", 740, GROUND_Y),
			("1_f", 800, 248), ("1_g", 950, 184), ("1_a", 1150, 248),
			("1_d", 1240, GROUND_Y)],
	}),
	("Grenadier", {                               # 两个 F 从高处扔，地面只有掩体墙
		"ledges": [(120, 256, 96), (300, 200, 128), (520, 248, 96), (700, 192, 128),
			(940, 248, 96), (1120, 192, 96)],
		"blocks": [(760, 64, 112)],
		"walls": [(200, 56), (560, 64), (900, 56)],
		"enemies": [("1_a", 250, GROUND_Y), ("1_f", 360, 200),
			("1_e", 500, None), ("1_g", 600, GROUND_Y), ("1_a", 640, GROUND_Y),
			("1_f", 740, 192), ("1_b", 980, 248), ("1_a", 1050, GROUND_Y),
			("1_g", 1150, 192), ("1_a", 1250, GROUND_Y)],
	}),
	("Skies", {                                   # 四个坑 + 三个 E：一边跳一边朝上打
		"gaps": [(180, 128), (420, 96), (640, 160), (900, 100)],
		"ledges": [(220, 272, 48), (340, 248, 80), (520, 216, 96), (690, 272, 64),
			(820, 248, 80), (1010, 248, 96), (1160, 200, 96)],
		"enemies": [("1_e", 250, None), ("1_c", 380, 248), ("1_g", 560, 216),
			("1_e", 700, None), ("1_a", 850, 248), ("1_b", 1060, 248),
			("1_e", 1100, None), ("1_a", 1200, 200), ("1_a", 1250, GROUND_Y)],
	}),
	("Crossfire", {                               # 三层高台交叉火力，底下又是一块堵死
		"ledges": [(120, 248, 160), (340, 200, 160), (560, 168, 240), (860, 248, 128),
			(1040, 200, 96), (1180, 152, 96)],
		"blocks": [(640, 64, 128)],
		"enemies": [("1_b", 180, 248), ("1_a", 260, GROUND_Y),
			("1_g", 400, 200), ("1_a", 560, GROUND_Y), ("1_c", 600, 168),
			("1_f", 740, 168), ("1_g", 900, 248), ("1_a", 1080, 200),
			("1_b", 1220, 152), ("1_d", 1240, GROUND_Y)],
	}),
	("Gauntlet", {                                # 矮通道 + 三个坑 + 两个 D，一路被撵着走
		"crawl": [(140, 180), (620, 160)],
		"gaps": [(400, 96), (900, 100), (1080, 96)],
		"ledges": [(300, 248, 96), (490, 200, 96), (820, 248, 64), (1010, 248, 64)],
		"walls": [(1220, 40)],
		"enemies": [("1_a", 60, GROUND_Y), ("1_d", 360, GROUND_Y),
			("1_g", 340, 248), ("1_a", 540, 200), ("1_e", 600, None),
			("1_d", 850, GROUND_Y), ("1_c", 1040, 248),
			("1_a", 1200, GROUND_Y), ("1_b", 1250, GROUND_Y)],
	}),
	("BossArena", {                               # 打到门口还有一队守着
		"props": [("fence", 300, GROUND_Y), ("fountain", 800, GROUND_Y),
			("bench2", 560, GROUND_Y)],
		"walls": [(40, 56)],
		"ledges": [(200, 248, 96), (380, 200, 96), (620, 248, 112)],
		"enemies": [("1_g", 160, GROUND_Y), ("1_a", 260, 248),
			("1_g", 420, 200), ("1_a", 500, GROUND_Y), ("1_c", 660, 248),
			("1_boss", 1000, GROUND_Y)],
	}),
]


## 玩家出生点。
SPAWN = (64.0, GROUND_Y - STAND)


# ---------------------------------------------------------------- 第二关（工业区）的段落
#
# 和第一关同样是 10 段 = 20 屏，难度对齐（坑的宽度、墙的高度、堵块的高路都走同一套自检）。
# 这一关的新东西：
#   2-A 吊在画面顶边以上（`("air", HANG_Y)`），玩家走到脚下才砸下来——**这一关的伏击**；
#   2-D 抡锤，摆在窄道和矮通道出口，逼玩家在它起手之后退开；
#   2-F 自爆，摆在开阔地和窄道里，逼玩家提前打掉；
#   2-E 飞在头顶投弹，摆在坑区和空旷段；
#   Boss 区**多摆平台**（它飘在空中、不追出地盘，玩家得跳上去才够得着）。

PROP_FRAMES_2 = {"screen": 4, "conveyor": 4}
SCATTER_2 = ["barrel", "box", "crate", "bucket", "board", "barrel_rust", "box_open",
	"box", "barrel", "crate"]
TREES_2 = ["locker", "ladder", "flag", "sign", "extinguisher"]
SCATTER_SEED_2 = 20260925
FLYING_2 = {"2_e"}

ENEMIES_2 = {
	"2_a": "res://scenes/enemy_2_a.tscn",
	"2_b": "res://scenes/enemy_2_b.tscn",
	"2_c": "res://scenes/enemy_2_c.tscn",
	"2_d": "res://scenes/enemy_2_d.tscn",
	"2_e": "res://scenes/enemy_2_e.tscn",
	"2_f": "res://scenes/enemy_2_f.tscn",
	"2_boss": "res://scenes/boss_2.tscn",
}

## Boss 飘在这个高度：再高缆绳就够不着地面上的玩家（见 boss_operator.gd 的 arm_max_length）。
BOSS2_AIR_Y = 170.0

SECTIONS_2 = [
	("Yard", {                                    # 厂区门口：走两步、认识 2-C 和 2-B
		"props": [("conveyor", 300, GROUND_Y), ("screen", 620, GROUND_Y),
			("bench", 1180, GROUND_Y)],
		"ledges": [(280, 256, 96), (440, 208, 96), (660, 256, 112), (880, 208, 96),
			(1080, 248, 96)],
		"enemies": [("2_c", 740, 256), ("2_c", 800, GROUND_Y),
			("2_b", 940, GROUND_Y), ("2_c", 1120, 248), ("2_c", 1240, GROUND_Y)],
	}),
	("Catwalks", {                                # 爬钢架，头顶开始有直升机
		"ledges": [(100, 264, 96), (260, 216, 96), (420, 168, 128), (620, 160, 240),
			(900, 216, 96), (1080, 256, 112)],
		"walls": [(180, 40)],
		"gaps": [(1000, 88)],
		"blocks": [(660, 64, 112)],
		"enemies": [("2_c", 150, GROUND_Y), ("2_c", 300, 216), ("2_e", 500, None),
			("2_c", 480, 168), ("2_b", 660, GROUND_Y), ("2_c", 700, 160),
			("2_c", 820, 160), ("2_c", 950, 216), ("2_b", 1100, GROUND_Y),
			("2_c", 1140, 256)],
	}),
	("Ambush", {                                  # 第一次被从天而降的 Worker 砸
		"props": [("conveyor", 700, GROUND_Y)],
		"ledges": [(240, 248, 112), (420, 256, 80), (520, 200, 96), (820, 248, 96),
			(960, 256, 80), (1060, 200, 112)],
		"enemies": [("2_a", 320, (AIR, HANG_Y)), ("2_c", 280, 248),
			("2_a", 660, (AIR, HANG_Y)), ("2_b", 620, GROUND_Y),
			("2_c", 560, 200), ("2_a", 1000, (AIR, HANG_Y)), ("2_c", 880, 248),
			("2_b", 1140, GROUND_Y), ("2_c", 1120, 200)],
	}),
	("Presses", {                                 # 矮通道 + 堵死的下层：出口都有锤子兵
		"crawl": [(200, 200), (800, 180)],
		"blocks": [(520, 64, 112)],
		# 340 / 400 那两块是垫脚：从地面一跳最多上 72，直接上 160 的钢架跳不上去
		"ledges": [(340, 248, 80), (400, 208, 64), (440, 160, 240), (720, 248, 96),
			(1000, 200, 96), (1160, 256, 96)],
		"enemies": [("2_d", 460, GROUND_Y), ("2_c", 500, 160),
			("2_d", 760, GROUND_Y), ("2_c", 760, 248), ("2_e", 900, None),
			("2_c", 1040, 200), ("2_d", 1120, GROUND_Y), ("2_c", 1200, 256)],
	}),
	("Sumps", {                                   # 坑区：直升机在头上投弹，逼你不能慢慢跳
		"gaps": [(300, 96), (620, 88), (940, 100)],
		"ledges": [(180, 248, 96), (460, 264, 96), (760, 248, 112), (1080, 256, 96)],
		"enemies": [("2_c", 200, 248), ("2_e", 340, None), ("2_c", 500, 264),
			("2_b", 760, GROUND_Y), ("2_c", 800, 248), ("2_e", 880, None),
			("2_f", 1060, GROUND_Y), ("2_c", 1120, 256), ("2_c", 1240, GROUND_Y)],
	}),
	("Sirens", {                                  # 自爆机的地盘：开阔，但它们冲得快
		"props": [("screen", 400, GROUND_Y)],
		"ledges": [(220, 256, 96), (460, 256, 80), (560, 208, 112), (900, 256, 96),
			(1020, 256, 80), (1120, 208, 96)],
		"walls": [(740, 56)],
		"enemies": [("2_f", 180, GROUND_Y), ("2_c", 260, 256), ("2_f", 620, GROUND_Y),
			("2_c", 600, 208), ("2_f", 820, GROUND_Y), ("2_c", 940, 256),
			("2_b", 1060, GROUND_Y), ("2_f", 1180, GROUND_Y), ("2_c", 1160, 208)],
	}),
	("Skyline", {                                 # 空战段：一路都在浮台上，头顶三架
		"gaps": [(360, 92), (820, 96)],
		"ledges": [(180, 264, 96), (320, 216, 112), (520, 264, 96), (700, 216, 112),
			(900, 264, 96), (1080, 216, 112)],
		"enemies": [("2_e", 260, None), ("2_c", 360, 216), ("2_e", 600, None),
			("2_c", 560, 264), ("2_c", 740, 216), ("2_e", 940, None),
			("2_c", 940, 264), ("2_a", 1140, (AIR, HANG_Y)), ("2_c", 1120, 216)],
	}),
	("Crossfire", {                               # 三层交叉火力
		"ledges": [(120, 264, 128), (340, 208, 128), (560, 152, 160), (820, 208, 128),
			(1040, 264, 128)],
		"gaps": [(700, 92)],
		"enemies": [("2_c", 160, 264), ("2_b", 260, GROUND_Y), ("2_c", 380, 208),
			("2_c", 600, 152), ("2_c", 660, 152), ("2_e", 700, None),
			("2_c", 860, 208), ("2_b", 980, GROUND_Y), ("2_c", 1080, 264),
			("2_d", 1200, GROUND_Y)],
	}),
	("Narrows", {                                 # 窄道：坑、矮通道、锤子兵和自爆机挤在一起
		"crawl": [(160, 180), (660, 160)],
		"gaps": [(420, 96), (900, 100), (1090, 92)],
		"ledges": [(320, 248, 96), (520, 184, 96), (840, 248, 64), (1020, 248, 64)],
		"walls": [(1220, 40)],
		"blocks": [(540, 56, 112)],
		"enemies": [("2_d", 380, GROUND_Y), ("2_c", 360, 248), ("2_f", 620, GROUND_Y),
			("2_c", 560, 184), ("2_e", 620, None), ("2_d", 870, GROUND_Y),
			("2_c", 860, 248), ("2_f", 1000, GROUND_Y), ("2_b", 1200, GROUND_Y)],
	}),
	("BossArena", {                               # Boss 区：**多摆平台**，它飘在空中要跳上去打
		"props": [("conveyor", 260, GROUND_Y), ("screen", 620, GROUND_Y)],
		"walls": [(40, 56)],
		"ledges": [(180, 248, 96), (360, 200, 96), (560, 248, 112),
			(760, 216, 128), (960, 256, 112), (1120, 208, 112),
			(880, 160, 96), (1060, 152, 96)],
		"enemies": [("2_d", 140, GROUND_Y), ("2_c", 220, 248), ("2_f", 420, GROUND_Y),
			("2_c", 400, 200), ("2_b", 620, GROUND_Y), ("2_c", 600, 248),
			("2_boss", 1000, (AIR, BOSS2_AIR_Y))],
	}),
]

# ---------------------------------------------------------------- 一关 = 一条配置
#
# 加一关就往这张表里加一条，跑 `python tools/level_build.py 2`。
# 关卡之间**什么都不共用**：敌人、装饰、段落各写各的——23 关里每一关的敌人和素材都不一样，
# 共用一份只会让「调第二关的节奏」把第一关也改掉。
STAGES = {
	"1": {
		"out": "level_1.tscn", "root": "Level1", "prop_dir": "cyberpunk",
		"sections": SECTIONS_1, "enemies": ENEMIES_1, "flying": FLYING_1,
		"prop_frames": PROP_FRAMES_1, "scatter": SCATTER_1, "trees": TREES_1,
		"seed": SCATTER_SEED_1,
	},
	"2": {
		"out": "level_2.tscn", "root": "Level2", "prop_dir": "industrial",
		"sections": SECTIONS_2, "enemies": ENEMIES_2, "flying": FLYING_2,
		"prop_frames": PROP_FRAMES_2, "scatter": SCATTER_2, "trees": TREES_2,
		"seed": SCATTER_SEED_2,
	},
}


def use_stage(key):
	"""把这一关的表装进全局，后面的代码照常读。"""
	global OUT, ROOT, PROP_DIR, SECTIONS, ENEMIES, FLYING
	global PROP_FRAMES, SCATTER, TREES, SCATTER_SEED
	stage = STAGES[key]
	OUT = os.path.join(SCENES, stage["out"])
	ROOT = stage["root"]
	PROP_DIR = stage["prop_dir"]
	SECTIONS = stage["sections"]
	ENEMIES = stage["enemies"]
	FLYING = stage["flying"]
	PROP_FRAMES = stage["prop_frames"]
	SCATTER = stage["scatter"]
	TREES = stage["trees"]
	SCATTER_SEED = stage["seed"]


# ---------------------------------------------------------------- 摊平成一整关

class Level:
	def __init__(self):
		self.width = SECTION * len(SECTIONS)
		self.gaps = []        # (x, 宽)
		self.ledges = []      # (名字, x, 顶边 y, 宽)
		self.walls = []       # (名字, x, 高)
		self.blocks = []      # (名字, x, 宽, 高)
		self.crawls = []      # (名字, x, 宽)
		self.enemies = []     # (名字, 类型, x, y)
		self.floating = set() # 直接摆在半空里的那几个的名字（吊着的 2-A、飘着的 Boss）
		self.props = []       # (名字, 装饰名, x, 底边 y)
		self.ground = []      # (x, 宽)
		self._build()

	def _build(self):
		counts = {}

		def name(prefix):
			counts[prefix] = counts.get(prefix, 0) + 1
			return "%s%d" % (prefix, counts[prefix])

		for index, (label, parts) in enumerate(SECTIONS):
			base = index * SECTION
			for x, wide in parts.get("gaps", []):
				self.gaps.append((base + x, wide))
			for x, top, wide in parts.get("ledges", []):
				self.ledges.append((name("Ledge"), base + x, top, wide))
			for x, high in parts.get("walls", []):
				self.walls.append((name("Wall"), base + x, high))
			for x, wide, high in parts.get("blocks", []):
				self.blocks.append((name("Block"), base + x, wide, high))
			for x, wide in parts.get("crawl", []):
				self.crawls.append((name("Crawl"), base + x, wide))
			for prop, x, surface in parts.get("props", []):
				self.props.append((name("Prop"), prop, base + x, surface))
			for kind, x, surface in parts.get("enemies", []):
				floats = False
				if surface is None:
					y = FLY_Y
				elif isinstance(surface, tuple) and surface[0] == AIR:
					y = surface[1]
					floats = True
				else:
					y = surface - (BOSS_STAND if kind.endswith("_boss") else STAND)
				# **名字必须各不相同**：一段里有好几个 1-A，重名的话 `.tscn` 里会出现同名节点，
				# 引擎的子节点名字表就对不上了（free 一批敌人时刷一屏
				# 「Children name does not match parent name in hashtable」）。
				label = name(enemy_label(kind) + "-")
				if floats:
					self.floating.add(label)
				self.enemies.append((label, kind, base + x, y))
		self.ground = self._ground_runs()
		self._scatter()

	def _scatter(self):
		"""沿着地面撒小东西和树。**自己写的线性同余**，不用 random：
		产物要进仓库，换台机器、换个 Python 版本都得生成出一模一样的文件。"""
		state = [SCATTER_SEED]

		def roll(low, high):
			state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
			return low + state[0] % max(1, high - low)

		count = [len(self.props)]

		def add(prop, x):
			count[0] += 1
			self.props.append(("Prop%d" % count[0], prop, float(x), GROUND_Y))

		for left, wide in self.ground:
			right = left + wide
			at = left + 24
			while at < right - 24:
				add(SCATTER[roll(0, len(SCATTER))], at)
				at += roll(SCATTER_STEP[0], SCATTER_STEP[1])
			at = left + roll(60, 200)
			while at < right - 80:
				add(TREES[roll(0, len(TREES))], at)
				at += roll(TREE_STEP[0], TREE_STEP[1])

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
	for name, x, wide, high in level.blocks:
		if high < MIN_BLOCK:
			problems.append("%s 只有 %.0f 高，一跳就过去了，堵不住（至少 %.0f）" % (name, high, MIN_BLOCK))
		if level.surface_at(x) is None or level.surface_at(x + wide) is None:
			problems.append("%s 架在坑上" % name)
		top = GROUND_Y - high
		over = [lx for _, lx, ltop, lwide in level.ledges
			if ltop <= top - BLOCK_CLEAR and lx <= x and lx + lwide >= x + wide]
		if not over:
			problems.append("%s 把路堵死了，上面却没有整块盖过去的浮台" % name)
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
	# 敌人：出生点那一屏不许有；站在地上的不能悬空，也不能塞进矮通道（32 高，净空只有 30，会卡死）
	for name, kind, x, y in level.enemies:
		if x < SAFE_START:
			problems.append("%s 摆在 x %.0f，出生点那一屏里（%.0f 以内不许放），人一进来就在挨打"
				% (name, x, SAFE_START))
		if kind in FLYING or name in level.floating:
			# 飞的、以及吊在画面上边的：脚下本来就没有面。
			# 吊着的那个要落得下来——底下得是实地，不能是坑。
			if y < 0.0 and level.surface_at(x) is None:
				problems.append("%s 吊在 x %.0f 的坑上面，掉下来就摔死了" % (name, x))
			continue
		feet = y + (BOSS_STAND if kind.endswith("_boss") else STAND)
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


def build(level, write):
	ids = {}
	extra = []
	for index, kind in enumerate(sorted({e[1] for e in level.enemies})):
		ids[kind] = "e%d" % index
		extra.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (ENEMIES[kind], ids[kind]))

	prop_ids = {}
	for index, prop in enumerate(sorted({p[1] for p in level.props})):
		prop_ids[prop] = "p%d" % index
		extra.append('[ext_resource type="Texture2D" path="res://skins/%s/props/%s.png" id="%s"]'
			% (PROP_DIR, prop, prop_ids[prop]))
	extra.append('[ext_resource type="Script" path="res://scripts/prop.gd" id="21"]')
	out = [HEAD + "\n".join(extra) + "\n"]
	out.append('\n[node name="Level1" type="Node2D"]\nscript = ExtResource("3")\n')
	# **装饰在最前面声明**：关卡加载时背景会被插成第 0 个子节点，于是画的顺序就是
	# 背景 → 装饰 → 地形 → 敌人 → 玩家，装饰再密也压不住要看的东西。
	out.append('\n[node name="Props" type="Node2D" parent="."]\n')
	for name, prop, x, bottom in level.props:
		frames = PROP_FRAMES.get(prop, 1)
		out.append('\n[node name="%s" type="Sprite2D" parent="Props"]\n'
			'texture = ExtResource("%s")\n'
			'script = ExtResource("21")\n'
			'position = Vector2(%g, %g)\n' % (name, prop_ids[prop], x, bottom))
		if frames > 1:
			out.append("frames = %d\n".replace("\n", chr(10)) % frames)
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
	for name, x, wide, high in level.blocks:
		out.append("\n" + platform(name, "Level", x, GROUND_Y - high, wide, high))
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
	out.append('\n[node name="ClearScreen" parent="." instance=ExtResource("22")]\n')

	if write:
		with open(OUT, "w", newline="\n", encoding="utf-8") as f:
			f.write("".join(out))
	return "".join(out)


def main():
	write = "--check" not in sys.argv
	wanted = [a for a in sys.argv[1:] if not a.startswith("--")] or list(STAGES)
	for key in wanted:
		if key not in STAGES:
			sys.exit("没有第 %s 关（有的是 %s）" % (key, "、".join(STAGES)))
		use_stage(key)
		build_stage(key, write)


def build_stage(key, write):
	level = Level()
	problems = check_level(level)
	if problems:
		print("关卡自检没过：")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	build(level, write)
	print("第 %s 关：%d 宽（%d 段 / %d 屏）" % (key, level.width, len(SECTIONS), level.width // 640))
	print("  地面 %d 段、坑 %d 个（最宽 %.0f，走着跳的上限 %.0f）"
		% (len(level.ground), len(level.gaps),
			max([w for _, w in level.gaps] or [0]), MAX_GAP))
	print("  浮台 %d、竖墙 %d、矮通道 %d、堵块 %d"
		% (len(level.ledges), len(level.walls), len(level.crawls), len(level.blocks)))
	print("  装饰 %d 件（纯显示，画在所有东西后面）" % len(level.props))
	kinds = {}
	for _, kind, _, _ in level.enemies:
		kinds[kind] = kinds.get(kind, 0) + 1
	print("  敌人 %d 个：%s" % (len(level.enemies),
		"、".join("%s×%d" % (k, n) for k, n in sorted(kinds.items()))))
	if write:
		print("  写入 scenes/%s" % STAGES[key]["out"])


if __name__ == "__main__":
	main()
