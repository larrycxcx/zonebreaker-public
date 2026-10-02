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
import struct
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

## **机关**（第二关，2026-10 加的）：液压机和闸门都是一帧 32×64、底边落在地面上。
## 液压机挂在「压机通道」的天花板下面（天花板从画面顶一直垂到离地 64），闸门上面是一截通到画面顶的实心墙——
## 门和压机都只有 64 高、一跳有 87，不封顶的话直接跳过去，机关就白放了。
TRAP_W = 32.0
TRAP_H = 64.0
TRAP_TOP = GROUND_Y - TRAP_H
## 一排液压机依次错开多少秒：同时砸下来就是一堵墙，错开了空当才是一台接一台地开。
PRESS_STAGGER = 0.45
PRESS_SCENE = "res://scenes/trap_press.tscn"
GATE_SCENE = "res://scenes/trap_gate.tscn"

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
	("Presses", {                                 # 压机通道 → 矮通道 + 堵死的下层：出口都有锤子兵
		# 开头一条压机通道（天花板 + 三台液压机，节奏依次错开）：从底下看准空当冲过去
		"halls": [(16, 160, 3)],
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
		# 闸门：自爆机冲过来的路上隔一道门，门一开它们就涌过来
		"gates": [(392, 0.0)],
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
		# 闸门：上面三层在打，底下这道门逼你在火力底下停一下
		"gates": [(504, 1.0)],
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

# ---------------------------------------------------------------- 第三关（酒吧街）的段落
#
# 同样 10 段 = 20 屏，几何走同一套自检。这一关**没有会飞的**，空中的压力换成了：
#   3-C 跳劈——唯一会主动越过地形的，摆在阶梯和屋顶段，躲在掩体后面对它没用；
#   3-E 贴地开枪——趴下躲不掉、只能跳，摆在开阔地和坑边；
#   3-D 正面减伤——摆在窄处和墙后，逼玩家绕背、跳过去或者把手雷扔过它头顶；
#   3-A 突进刺——摆在**地面**上（冲的时候不在悬崖前掉头，摆在浮台上它会自己冲下去）；
#   3-F 炮车——慢慢挪、停下来**从炮管里打手雷**，摆在长直路上。
# Boss 是**站在地上的**，所以 Boss 区那一段**整片实地、不放墙**：
# 墙挡在它和玩家之间时，视线从身体中心发出会被挡住，它就什么都不做（见 CLAUDE.md）。

## **不摆酒瓶、酒杯、飞钞、飘牌**（2026-10 试玩反馈）：这几样小小一个、亮晶晶地摆在地上，
## 在一个打怪掉钱的游戏里看着就是「能捡的东西」，玩家会走过去试着捡。
## 装饰只留一眼看得出是家具的大件。这一关因此没有会动的装饰。
PROP_FRAMES_3 = {}
SCATTER_3 = ["crate", "stool", "bin", "keg", "stool2", "crate", "keg", "bin"]
TREES_3 = ["cabinet", "sign", "counter", "cabinet2", "counter2"]
SCATTER_SEED_3 = 20261001
## 街边那一排楼（`terrain_build.py` 按配方拼出来的整张图）。沿着地面一栋挨一栋摆，
## 楼与楼之间留一截空当露出后面的夜景；**只摆在实地上**，坑上面立着一栋楼就不像话了。
FACADES_3 = ["facade_1", "facade_2", "facade_3", "facade_4", "facade_5", "facade_6"]
FACADE_GAP = (16, 120)

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

# ---------------------------------------------------------------- 第四关（地下室，纵向往上爬）的段落
#
# 尺子和写场景都在 `vlevel_build.py`（纵向关的规矩和横向完全不同）。这里只有数据。
# 一段 = 一屏 = 6 层，层从下往上数；每层写这一层的单向平台 (x, 宽)，竖井里面是 x 32..608。
# 敌人 (类型, 层, x)；层写 "b0" 是站在这一段第 0 块实心块上，写 ("air", 层) 是会飞的悬在那一层。
#
# 节奏：每隔 5 段有一层「歇脚层」（一整层宽平台、敌人少）；会飞的贴着两侧墙（x 64 / 576）；
# 实心块（`blocks`）是这一关的「堵路」——从下面穿不上去，得绕。
ENEMIES_4 = {
	"4_a": "res://scenes/enemy_4_a.tscn",
	"4_b": "res://scenes/enemy_4_b.tscn",
	"4_c": "res://scenes/enemy_4_c.tscn",
	"4_d": "res://scenes/enemy_4_d.tscn",
	"4_e": "res://scenes/enemy_4_e.tscn",
	"4_f": "res://scenes/enemy_4_f.tscn",
	"4_boss": "res://scenes/boss_4.tscn",
}
FLYING_4 = {"4_d"}
## 蜘蛛炮台矮（判定框 22 高），脚底在原点下方 11。
STAND_4 = {"4_e": 11.0}
PROPS_4_SMALL = ["box", "box_moss", "box_small", "pipe", "pipe_moss", "grass", "grass2", "grate", "fan"]
PROPS_4_BIG = ["container", "container_moss", "pipe_bend", "pipe_bend_moss", "crane", "sign_hotel",
	"sign_poker", "sign_carre", "smoke", "unit", "pipe_tall"]
PROP_FRAMES_4 = {"smoke": 6}
SCATTER_SEED_4 = 20261002

SECTIONS_4 = [
	("Floor", {                                   # 出生那一屏：没有敌人，先学会往上跳
		"rows": [[(48, 192)], [(224, 192)], [(400, 176)], [(224, 160)], [(48, 192)], [(240, 176)]],
	}),
	("FirstShots", {                              # 第一次被从上面打：三向枪手往下斜射
		"rows": [[(400, 192)], [(176, 256)], [(48, 160), (432, 144)], [(192, 256)], [(400, 176)],
			[(160, 192)]],
		"enemies": [("4_e", 1, 300), ("4_c", 3, 320), ("4_b", 4, 480)],
	}),
	("Climber", {                                 # 追兵从下面追上来
		"rows": [[(176, 192)], [(368, 208)], [(96, 224)], [(288, 224)], [(448, 144)], [(240, 192)]],
		"enemies": [("4_a", 1, 470), ("4_c", 2, 200), ("4_c", 3, 400), ("4_a", 5, 330),
			("4_e", 4, 520)],
	}),
	("Guards", {                                  # 平台守卫：她那一层别上去，先从下面斜着打掉
		"rows": [[(48, 176)], [(224, 224)], [(432, 144)], [(160, 256)], [(48, 160)], [(224, 224)]],
		"enemies": [("4_b", 1, 330), ("4_e", 2, 500), ("4_b", 3, 290), ("4_c", 5, 400),
			("4_f", 4, 120)],
	}),
	("Drones", {                                  # 无人机第一次出现：贴着两侧墙跟你的高度
		"rows": [[(416, 176)], [(176, 256)], [(432, 160)], [(256, 224)], [(48, 224)], [(304, 192)]],
		"enemies": [("4_e", 1, 300), ("4_d", (AIR, 2), 64), ("4_c", 3, 380), ("4_d", (AIR, 4), 576),
			("4_c", 5, 400)],
	}),
	("Rest", {                                    # 歇脚层
		"rows": [[(304, 224)], [(64, 512)], [(96, 160)], [(288, 160)], [(448, 144)], [(224, 192)]],
		"enemies": [("4_e", 1, 480), ("4_c", 5, 320), ("4_b", 3, 368)],
	}),
	("Shovers", {                                 # 窄台子 + 打飞人的：被抡下去就白爬
		"rows": [[(128, 128)], [(288, 128)], [(448, 128)], [(288, 128)], [(128, 128)], [(256, 192)]],
		"enemies": [("4_f", 1, 352), ("4_d", (AIR, 2), 64), ("4_f", 3, 352), ("4_f", 5, 380),
			("4_c", 2, 512)],
	}),
	("Overhangs", {                               # 实心块：从下面穿不上去，得绕到旁边跳
		"rows": [[(64, 224)], [(240, 240)], [(400, 176)], [(240, 192)], [(48, 192)], [(208, 224)]],
		"blocks": [(32, 2, 240), (384, 4, 224)],
		"enemies": [("4_b", 1, 400), ("4_e", "b0", 120), ("4_c", "b1", 500), ("4_a", 5, 300),
			("4_c", 3, 330)],
	}),
	("Crossfire", {                               # 左右交替的枪手
		"rows": [[(304, 224)], [(64, 256)], [(352, 224)], [(96, 224)], [(352, 224)], [(128, 256)]],
		"enemies": [("4_c", 1, 120), ("4_c", 2, 520), ("4_c", 3, 140), ("4_c", 4, 500),
			("4_d", (AIR, 5), 576)],
	}),
	("Climbers", {                                # 两个追兵 + 打飞人的
		"rows": [[(416, 176)], [(192, 256)], [(48, 192)], [(240, 176)], [(448, 144)], [(224, 224)]],
		"enemies": [("4_a", 1, 300), ("4_e", 2, 120), ("4_a", 3, 330), ("4_f", 5, 330),
			("4_c", 4, 520)],
	}),
	("Rest2", {                                   # 歇脚层
		"rows": [[(240, 192)], [(64, 512)], [(400, 176)], [(192, 192)], [(48, 176)], [(256, 192)]],
		"enemies": [("4_e", 1, 160), ("4_d", (AIR, 3), 576), ("4_c", 5, 350)],
	}),
	("GuardsShovers", {                           # 守卫和打飞人的交替
		"rows": [[(432, 160)], [(224, 224)], [(48, 192)], [(272, 192)], [(448, 144)], [(224, 192)]],
		"enemies": [("4_b", 1, 330), ("4_c", 2, 120), ("4_f", 3, 370), ("4_b", 5, 320),
			("4_e", 4, 520)],
	}),
	("DroneAlley", {                              # 窄台子、三架无人机
		"rows": [[(48, 192)], [(256, 128)], [(400, 128)], [(256, 128)], [(96, 128)], [(240, 160)]],
		"enemies": [("4_d", (AIR, 1), 576), ("4_d", (AIR, 3), 64), ("4_d", (AIR, 5), 576),
			("4_c", 5, 330), ("4_e", 0, 150)],
	}),
	("Overhangs2", {                              # 第二段实心块
		"rows": [[(256, 192)], [(416, 176)], [(224, 192)], [(48, 160)], [(192, 224)], [(416, 160)]],
		"blocks": [(32, 1, 240), (400, 3, 208)],
		"enemies": [("4_e", "b0", 150), ("4_c", "b1", 500), ("4_a", 4, 300), ("4_f", 5, 480),
			("4_c", 2, 320)],
	}),
	("Spiders", {                                 # 炮台一层一层地封
		"rows": [[(192, 224)], [(432, 160)], [(176, 272)], [(48, 176)], [(256, 224)], [(64, 224)]],
		"enemies": [("4_e", 0, 300), ("4_c", 1, 520), ("4_e", 2, 300), ("4_d", (AIR, 3), 576),
			("4_e", 4, 360)],
	}),
	("Rest3", {                                   # 歇脚层
		"rows": [[(288, 224)], [(64, 512)], [(96, 176)], [(304, 160)], [(464, 128)], [(272, 176)]],
		"enemies": [("4_c", 1, 480), ("4_b", 1, 160), ("4_e", 3, 380)],
	}),
	("Gauntlet", {                                # 什么都来一点
		"rows": [[(96, 192)], [(304, 192)], [(128, 192)], [(352, 192)], [(160, 208)], [(384, 176)]],
		"enemies": [("4_f", 1, 400), ("4_b", 2, 220), ("4_f", 3, 450), ("4_c", 4, 260),
			("4_d", (AIR, 5), 64)],
	}),
	("LastClimb", {                               # 最后一段：追兵 + 枪手 + 炮台
		"rows": [[(176, 224)], [(432, 144)], [(224, 224)], [(48, 192)], [(256, 192)], [(448, 128)]],
		"enemies": [("4_a", 0, 290), ("4_d", (AIR, 1), 64), ("4_c", 2, 340), ("4_c", 3, 140),
			("4_e", 4, 350)],
	}),
	("Approach", {                                # Boss 区底下那一段，最上面一层就是 Boss 区的地板
		"rows": [[(240, 208)], [(64, 192)], [(288, 192)], [(96, 192)], [(320, 224)], [(32, 576)]],
		"enemies": [("4_b", 1, 160), ("4_f", 2, 380), ("4_c", 3, 200), ("4_e", 4, 430)],
	}),
	("BossArena", {                               # Boss 区（地板在 y=320）
		"rows": [[(64, 160), (416, 160)], [(224, 192)]],
		# 骷髅头飘在右侧。**它最低的位置 = 激光对准站在地板上的人**：地板 320、人的身体中心 304、
		# 激光出口在它身体中心下面 16，所以是 288。另一侧在 x 96（`lane_offset` -448），往上最多飘 240
		"enemies": [("4_boss", ("at", 288), 544)],
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
	"3": {
		"out": "level_3.tscn", "root": "Level3", "prop_dir": "bar_street",
		"sections": SECTIONS_3, "enemies": ENEMIES_3, "flying": set(),
		"prop_frames": PROP_FRAMES_3, "scatter": SCATTER_3, "trees": TREES_3,
		"seed": SCATTER_SEED_3, "stand": STAND_3, "facades": FACADES_3,
	},
	# 第四关是**纵向**的：段落、尺子、写场景都走 `vlevel_build.py`
	"4": {
		"out": "level_4.tscn", "root": "Level4", "prop_dir": "basement", "vertical": True,
		"sections": SECTIONS_4, "enemies": ENEMIES_4, "flying": FLYING_4,
		"prop_frames": PROP_FRAMES_4, "small": PROPS_4_SMALL, "big": PROPS_4_BIG,
		"seed": SCATTER_SEED_4, "stand": STAND_4,
	},
}


def use_stage(key):
	"""把这一关的表装进全局，后面的代码照常读。"""
	global OUT, ROOT, PROP_DIR, SECTIONS, ENEMIES, FLYING
	global PROP_FRAMES, SCATTER, TREES, SCATTER_SEED, STAND_BY, FACADES
	stage = STAGES[key]
	OUT = os.path.join(SCENES, stage["out"])
	ROOT = stage["root"]
	PROP_DIR = stage["prop_dir"]
	SECTIONS = stage["sections"]
	ENEMIES = stage["enemies"]
	FLYING = stage["flying"]
	PROP_FRAMES = stage["prop_frames"]
	SCATTER = stage.get("scatter", [])
	TREES = stage.get("trees", [])
	SCATTER_SEED = stage["seed"]
	STAND_BY = stage.get("stand", {})
	FACADES = stage.get("facades", [])


def stand_of(kind):
	"""脚底在原点下方几像素：表里点了名的按表，否则 Boss 24、别人 16。"""
	if kind in STAND_BY:
		return STAND_BY[kind]
	return BOSS_STAND if kind.endswith("_boss") else STAND


def prop_width(prop):
	"""装饰贴图有多宽（读 PNG 头，楼面是 `terrain_build.py` 先生成好的）。"""
	path = os.path.join(HERE, "..", "skins", PROP_DIR, "props", prop + ".png")
	with open(path, "rb") as f:
		return struct.unpack(">I", f.read(24)[16:20])[0]


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
		self.halls = []       # (名字, x, 宽)       压机通道的天花板
		self.presses = []     # (名字, x, 错开几秒)
		self.gates = []       # (名字, x, 错开几秒)
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
			for x, wide, count in parts.get("halls", []):
				self.halls.append((name("Hall"), base + x, wide))
				space = (wide - count * TRAP_W) / (count + 1)
				for k in range(count):
					self.presses.append((name("Press"), base + x + space * (k + 1) + TRAP_W * k,
						PRESS_STAGGER * k))
			for x, phase in parts.get("gates", []):
				self.gates.append((name("Gate"), base + x, phase))
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
					y = surface - stand_of(kind)
				# **名字必须各不相同**：一段里有好几个 1-A，重名的话 `.tscn` 里会出现同名节点，
				# 引擎的子节点名字表就对不上了（free 一批敌人时刷一屏
				# 「Children name does not match parent name in hashtable」）。
				label = name(enemy_label(kind) + "-")
				if floats:
					self.floating.add(label)
				self.enemies.append((label, kind, base + x, y))
		self.ground = self._ground_runs()
		self._scatter()
		# 楼面**排在所有装饰最前面**：先声明的先画，楼要在吧台、酒桶后面
		self.props = self._facades() + self.props

	def _facades(self):
		"""沿着每一段地面一栋挨一栋摆楼，放不下整栋就不放（不许悬在坑上）。
		种子和小装饰的分开，加楼不会打乱原来那些小东西的位置。"""
		if not FACADES:
			return []
		state = [SCATTER_SEED + 1]

		def roll(low, high):
			state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
			return low + state[0] % max(1, high - low)

		out = []
		for left, wide in self.ground:
			at = left + roll(0, 48)
			while True:
				facade = FACADES[roll(0, len(FACADES))]
				width = prop_width(facade)
				if at + width > left + wide - 8:
					break
				out.append(("Facade%d" % (len(out) + 1), facade, float(at), GROUND_Y))
				at += width + roll(FACADE_GAP[0], FACADE_GAP[1])
		return out

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
	# 机关：底下是实地；那一条（压机通道 / 闸门连同上面那截墙）不许和平台、矮通道、堵块、竖墙打架；
	# 跟前不许站敌人（站在压机底下的巡逻兵一直挨不着，站在门里的会被门卡住）
	columns = [(n, x, wide) for n, x, wide in level.halls] + [(n, x, TRAP_W) for n, x, _ in level.gates]
	for name, x, wide in columns:
		if level.surface_at(x) is None or level.surface_at(x + wide) is None:
			problems.append("%s 架在坑上" % name)
		for other, ox, _, owide in level.ledges:
			if ox < x + wide and x < ox + owide:
				problems.append("%s 那一条里有浮台 %s，会被天花板 / 门上的墙穿过去" % (name, other))
		solids = [(n, cx, cw) for n, cx, cw in level.crawls] + [(n, bx, bw) for n, bx, bw, _ in level.blocks] \
			+ [(n, wx, 16.0) for n, wx, _ in level.walls]
		for other, ox, owide in solids:
			if ox < x + wide + 16 and x - 16 < ox + owide:
				problems.append("%s 挨着 %s，挤在一起" % (name, other))
		for ename, kind, ex, ey in level.enemies:
			if x - 24 <= ex <= x + wide + 24 and ey > 0:
				problems.append("%s 站在 %s 那一条里" % (ename, name))
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
		feet = y + stand_of(kind)
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
	if level.presses:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t0"]' % PRESS_SCENE)
	if level.gates:
		extra.append('[ext_resource type="PackedScene" path="%s" id="t1"]' % GATE_SCENE)
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
	for name, x, wide in level.halls:
		out.append("\n" + platform(name, "Level", x, 0, wide, TRAP_TOP))
	for name, x, _ in level.gates:
		out.append("\n" + platform(name.replace("Gate", "Lintel"), "Level", x, 0, TRAP_W, TRAP_TOP))
	out.append('\n[node name="Walls" type="Node2D" parent="Level"]\n')
	for name, x, high in level.walls:
		out.append("\n" + platform(name, "Level/Walls", x, GROUND_Y - high, 16, high))

	if level.presses or level.gates:
		# 机关画在地形后面、敌人前面
		out.append('\n[node name="Traps" type="Node2D" parent="."]\n')
		for name, x, phase in level.presses:
			out.append('\n[node name="%s" parent="Traps" instance=ExtResource("t0")]\n'
				'position = Vector2(%g, %g)\nphase = %g\nmount_y = %g\n' % (name, x, TRAP_TOP, phase, TRAP_TOP))
		for name, x, phase in level.gates:
			out.append('\n[node name="%s" parent="Traps" instance=ExtResource("t1")]\n'
				'position = Vector2(%g, %g)\nphase = %g\n' % (name, x, TRAP_TOP, phase))
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


def build_map_demo(write):
	"""用户示意图那一屏（`level_maps.DEMO`），生成到 scenes/map_demo.tscn，不进选关列表。"""
	import level_maps
	import map_build as mb
	level = mb.MapLevel(level_maps.DEMO, level_maps.DEMO_ENEMIES, ENEMIES_2, lambda kind: STAND)
	problems = mb.check(level)
	if problems:
		print("格子地图自检没过：")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	mb.build(level, os.path.join(SCENES, "map_demo.tscn"), "MapDemo", "industrial", write)
	print("示意图那一段：%d 格宽（%d 像素）" % (level.width, level.width * mb.CELL))
	print("  实心 %d 块、单向 %d、梯子 %d、液压机 %d、闸门 %d、敌人 %d"
		% (len(level.solids), len(level.ledges), len(level.ladders), len(level.presses),
			len(level.gates), len(level.enemies)))
	if write:
		print("  写入 scenes/map_demo.tscn")


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


def build_vertical(key, write):
	import vlevel_build as vb
	stage = STAGES[key]
	level = vb.VLevel(stage["sections"], stage["enemies"], stage["flying"], stand_of)
	problems = vb.check(level)
	if problems:
		print("关卡自检没过：")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	vb.dress(level, stage["prop_dir"], stage["small"], stage["big"], stage["seed"])
	vb.build(level, os.path.join(SCENES, stage["out"]), stage["root"], stage["prop_dir"],
		stage["prop_frames"], write)
	print("第 %s 关（纵向）：%d × %d（%d 段 / %d 屏）" % (key, vb.WIDTH, vb.HEIGHT, len(stage["sections"]),
		vb.HEIGHT // vb.SCREEN_H))
	print("  浮台 %d、实心块 %d" % (len(level.ledges), len(level.blocks)))
	print("  装饰 %d 件" % len(level.props))
	kinds = {}
	for _, kind, _, _ in level.enemies:
		kinds[kind] = kinds.get(kind, 0) + 1
	print("  敌人 %d 个：%s" % (len(level.enemies),
		"、".join("%s×%d" % (k, n) for k, n in sorted(kinds.items()))))
	if write:
		print("  写入 scenes/%s" % stage["out"])


def build_stage(key, write):
	if STAGES[key].get("vertical"):
		build_vertical(key, write)
		return
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
	if level.presses or level.gates:
		print("  机关：液压机 %d（%d 条压机通道）、闸门 %d" % (len(level.presses), len(level.halls), len(level.gates)))
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
