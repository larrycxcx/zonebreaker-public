"""第一关（绿区）的分层版：一段一段画，`map_canvas.stitch()` 拼成一整关。

和第二关同一套设计原则（2026-10 用户定的）：
- **只有一个出口**（最后的 Boss）。十段里七段**必须绕路**（标 [绕]），三段**两条路随便挑**（标 [选]）。
- **敌人多、摆得合理**：会冲的（1-D 滑板手）只放在两头堵死的路上，路的尽头不许是坑；
  上下分层的地方多放会斜射的（1-B、1-C、炮台 1-G）。每一屏至少 4 个（`MIN_ENEMIES`）。
- **画面要满**：多摆树、草、石头、油桶、可打爆的箱子，不要大片空地。

绿区的「室内」是**山洞**：头顶有实心岩层的地方铺洞里的墙（见 `map_build.THEMES["green"]`）。
这是第一关，机关一样一样地教：第 1 段第一次爬梯子，第 3 段第一次钻山洞、第一次碰到要打烂的箱子，
第 4 段第一次靠钢梁过大坑。

字母表：a 1-A（巡逻兵，只打水平）、b 1-B（连发、会斜射）、c 1-C（远射、会趴下、会斜射）、
d 1-D（滑板手，冲撞）、e 1-E（无人机，往下放电）、f 1-F（扔手雷）、g 1-G（炮台，会斜射）、B Boss A。
行号：上层地板第 7 行、中层第 13 行、地面第 20 行；敌人写在**脚下那一行的上一行**。
"""

from map_canvas import Canvas, stitch

LETTERS = {"a": "1_a", "b": "1_b", "c": "1_c", "d": "1_d", "e": "1_e", "f": "1_f", "g": "1_g",
	"boss": "1_boss"}
FLOATING = {"1_e"}
HANGING = set()
CHASERS = {"1_d"}
MIN_ENEMIES = 4


def park():
	"""[绕] 第 1 段「公园入口」。第一屏不放敌人：几级草皮台子教你跳。
	第二屏地面被一座高过一跳的石山挡死，**第一次爬梯子**：顺梯子上山顶，从另一边的台阶下去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.put(3, 19, "@")
	cv.floor(12, 18, 16, "=")
	cv.floor(22, 28, 13, "=")
	cv.fill(30, 31, 12, 19, "!")
	cv.prop("tree_big", 6, 20)
	cv.prop("bench", 20, 20)
	cv.prop("tree_small", 34, 20)
	cv.prop("fountain", 38, 20)
	# 石山：48~55 列从第 8 行一直到地面，左边一架梯子
	cv.fill(48, 55, 8, 19, "%")
	cv.ladder(46, 8, 20)
	cv.floor(58, 64, 11, "=")
	cv.floor(66, 70, 15, "=")
	cv.put(51, 7, "g")
	cv.put(60, 10, "c")
	cv.put(66, 19, "a")
	cv.put(74, 19, "b")
	cv.barrel(76, 20)
	cv.prop("tree_small", 44, 20)
	cv.prop("tree_big", 72, 20)
	return cv


def terraces():
	"""[选] 第 2 段「阶梯」。两级草皮台阶上去是一条长长的石头走道（单向的），走道底下是地面。
	**走上面**：两个连发的枪手往下斜着打；**走下面**：滑板手冲过来（两头是台阶和石墩，冲不出去），
	箱子当掩体。两条路在另一头会合。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(6, 13, 16, 19)
	cv.fill(14, 21, 12, 19)
	cv.floor(22, 60, 12, ":")
	cv.fill(61, 66, 12, 19, "%")
	cv.fill(67, 72, 16, 19)
	cv.put(10, 15, "a")
	cv.put(20, 3, "e")
	cv.put(30, 11, "b")
	cv.put(36, 19, "d")
	cv.crates(32, 20, 1)
	cv.crates(48, 20, 1)
	cv.put(50, 11, "b")
	cv.put(56, 19, "a")
	cv.barrel(54, 20)
	cv.put(64, 11, "g")
	cv.put(76, 19, "c")
	cv.barrel(78, 20)
	cv.prop("tree_small", 2, 20)
	cv.prop("bush_big", 16, 12)
	cv.prop("tree_big", 74, 20)
	return cv


def burrow():
	"""[绕] 第 3 段「地洞」。一座平顶的山：洞口在左边被石头封死，得**先顺梯子上山顶**；
	山顶往右被一道通到天上的石崖挡住，只能从地上的洞口**掉进山洞**，在洞里打烂一整摞箱子、
	再顺洞里的梯子爬回山顶，从山的另一头下去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(3, 75, 13, 14)               # 山体（洞顶）
	cv.fill(3, 4, 15, 19, "%")           # 洞口封死
	cv.fill(74, 75, 15, 19, "%")         # 洞的右头
	cv.fill(48, 51, 0, 12, "%")          # 山顶上的石崖，一直通到画面顶
	cv.clear(40, 41, 13, 14)             # 掉进山洞的口子
	cv.ladder(1, 13, 20)
	cv.ladder(66, 13, 20)
	cv.crates(58, 20, 3)                 # 洞里一整摞箱子
	cv.put(10, 4, "e")
	cv.put(20, 12, "a")
	cv.put(32, 12, "b")
	cv.put(46, 12, "g")
	cv.put(24, 19, "d")
	cv.put(52, 19, "c")
	cv.barrel(54, 20)
	cv.put(64, 19, "c")
	cv.put(58, 12, "f")
	cv.put(70, 12, "a")
	cv.prop("tree_small", 14, 13)
	cv.prop("tree_big", 26, 13)
	cv.prop("tree_small", 62, 13)
	cv.prop("bush_wide", 36, 13)
	return cv


def chasm():
	"""[绕] 第 4 段「大坑」。地面中间断开 48 格，跳不过去：顺梯子爬上石台，
	在半空一串台子上跳过去（有高有低），无人机在头顶守着，台子上站着枪手。"""
	cv = Canvas(80)
	cv.ground(0, 15)
	cv.ground(64, 79)
	cv.floor(4, 20, 9, ":")
	cv.floor(25, 31, 8, "=")
	cv.floor(36, 42, 10, "=")
	cv.floor(47, 53, 9, "=")
	cv.floor(58, 66, 9, ":")
	cv.ladder(8, 9, 20)
	# 坑里立着几根石柱（背景），再加两块矮一点的石台：坑上面不是一片空
	cv.fill(22, 23, 14, 22, "!")
	cv.fill(33, 34, 15, 22, "!")
	cv.fill(44, 45, 12, 22, "!")
	cv.fill(55, 56, 14, 22, "!")
	cv.fill(28, 33, 14, 14, ":")
	cv.fill(50, 55, 15, 15, ":")
	cv.put(30, 13, "a")
	cv.put(52, 14, "b")
	cv.put(4, 19, "a")
	cv.put(14, 8, "g")
	cv.put(28, 3, "e")
	cv.put(38, 9, "b")
	cv.put(50, 8, "c")
	cv.put(56, 3, "e")
	cv.put(62, 8, "c")
	cv.put(72, 19, "a")
	cv.put(76, 19, "f")
	cv.prop("rock_big", 1, 20)
	cv.prop("tree_small", 68, 20)
	return cv


def fortress():
	"""[绕] 第 5 段「堡垒」。一座石头堡垒，**外墙没有门**：顺外墙的梯子上屋顶，
	从屋顶的洞掉进二楼，二楼尽头的洞再掉进一楼的后半间，从后门出去。
	一楼前半间是实心的地基。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(5, 74, 7, "%")              # 屋顶
	cv.fill(6, 7, 8, 19, "%")            # 前墙（没有门）
	cv.floor(8, 71, 13, "%")             # 二楼地板
	cv.fill(8, 45, 14, 19, "X")          # 一楼前半间是地基
	cv.fill(46, 47, 14, 19, "%")
	cv.fill(72, 73, 8, 15, "%")          # 后墙，下面 4 格是后门
	cv.clear(30, 31, 7, 7)               # 屋顶的洞
	cv.clear(60, 61, 13, 13)             # 二楼的洞
	cv.ladder(3, 7, 20)
	cv.fill(12, 13, 5, 6, "X")
	cv.fill(44, 45, 5, 6, "X")
	cv.put(10, 3, "e")
	cv.put(20, 6, "g")
	cv.put(36, 6, "b")
	cv.put(18, 12, "c")
	cv.barrel(22, 13)
	cv.put(28, 12, "a")
	cv.put(50, 12, "a")
	cv.put(66, 12, "f")
	cv.put(56, 19, "d")
	cv.put(66, 19, "c")
	cv.barrel(64, 20)
	cv.crates(52, 20, 1)
	cv.prop("tree_big", 76, 20)
	return cv


def trench():
	"""[选] 第 6 段「掷弹兵」。一道长长的土堤：**堤上**两个掷弹兵往下面扔手雷、一个枪手守着；
	**堤下**的通道里是连发的枪手和滑板手，身边堆着油桶。顺左头的梯子上堤，或者直接钻下面。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 74, 13, 14)
	cv.ladder(2, 13, 20)
	cv.fill(28, 29, 11, 12, "X")
	cv.fill(52, 53, 11, 12, "X")
	cv.put(16, 12, "f")
	cv.put(44, 12, "f")
	cv.put(60, 12, "c")
	cv.put(70, 12, "a")
	cv.put(30, 4, "e")
	cv.put(24, 19, "b")
	cv.barrel(26, 20)
	cv.put(34, 19, "d")
	cv.crates(40, 20, 2)
	cv.put(50, 19, "a")
	cv.crates(56, 20, 1)
	cv.put(64, 19, "b")
	cv.barrel(66, 20)
	cv.prop("tree_small", 8, 13)
	cv.prop("tree_big", 36, 13)
	cv.prop("bush_wide", 64, 13)
	cv.prop("tree_small", 77, 20)
	return cv


def islands():
	"""[绕] 第 7 段「空岛」。地面整个断开，只有一串浮在半空的小岛：一跳一跳过去，
	中间那座要顺梯子爬上更高的一座。无人机最多的一段。"""
	cv = Canvas(80)
	cv.ground(0, 5)
	cv.fill(4, 5, 18, 19)                # 坑沿一道矮沿：滑板手冲到这儿就停，不会自己掉下去
	cv.ground(74, 79)
	cv.fill(74, 75, 18, 19)
	cv.fill(8, 13, 16, 17)
	cv.fill(17, 22, 12, 13)
	cv.fill(27, 35, 12, 13)
	cv.fill(36, 41, 6, 7)
	cv.ladder(34, 6, 12)
	cv.fill(46, 51, 9, 10)
	cv.fill(56, 61, 13, 14)
	cv.fill(66, 71, 12, 13)
	cv.fill(14, 15, 15, 22, "!")
	cv.fill(52, 53, 16, 22, "!")
	cv.put(10, 15, "b")
	cv.put(20, 3, "e")
	cv.put(30, 11, "c")
	cv.put(38, 5, "g")
	cv.put(48, 3, "e")
	cv.put(48, 8, "b")
	cv.put(58, 12, "c")
	cv.put(64, 2, "e")
	cv.put(68, 11, "a")
	cv.put(76, 19, "a")
	cv.prop("tree_small", 18, 12)
	cv.prop("bush_flat", 57, 13)
	return cv


def crossfire():
	"""[绕] 第 8 段「三层交叉火力」。一楼前半间到头是墙，梯子上二楼；二楼走到一半被墙挡住，
	梯子上屋顶、从屋顶的洞掉回二楼后半截，再从二楼的洞掉进一楼后半间出去。
	二楼前半截有一截是单向的石台：底下的枪手往上斜着打得到你，你也打得到他。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(10, 79, 7, "%")             # 屋顶
	cv.fill(0, 79, 13, 14)               # 二楼地板（也是一楼的顶）
	cv.floor(6, 15, 13, ":")             # 其中一截是单向的
	cv.clear(6, 15, 14, 14)
	cv.fill(24, 25, 15, 19, "%")         # 一楼前半间到头
	cv.fill(50, 51, 8, 12, "%")          # 二楼走到一半的墙
	cv.clear(62, 63, 7, 7)               # 屋顶的洞
	cv.clear(74, 75, 13, 14)             # 二楼后半截的洞
	cv.ladder(18, 13, 20)
	cv.ladder(44, 7, 13)
	cv.put(8, 19, "a")
	cv.put(14, 19, "c")
	cv.put(12, 12, "b")
	cv.put(30, 12, "c")
	cv.put(4, 3, "e")
	cv.put(56, 6, "g")
	cv.put(66, 6, "b")
	cv.put(60, 12, "c")
	cv.barrel(62, 13)
	cv.put(70, 12, "a")
	cv.put(40, 19, "d")
	cv.put(56, 19, "f")
	cv.barrel(58, 20)
	cv.crates(66, 20, 1)
	cv.put(72, 19, "c")
	cv.fill(30, 31, 5, 6, "X")
	cv.prop("tree_small", 2, 13)
	return cv


def tunnel():
	"""[绕] 第 9 段「窄道」。一条又长又低的地道，一条道走到底：滑板手迎面冲过来，
	**两摞箱子把地道堵死**（打烂才过得去），枪手身边堆着油桶。地道顶上是长满树的山坡，上不去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 75, 13, 14)
	cv.fill(4, 7, 0, 12, "%")            # 山坡左头一道石崖：地道顶上的山坡上不去
	cv.crates(26, 20, 3)
	cv.crates(52, 20, 3)
	cv.put(8, 19, "b")
	cv.put(14, 19, "d")
	cv.put(20, 19, "a")
	cv.put(32, 19, "c")
	cv.barrel(34, 20)
	cv.put(40, 19, "d")
	cv.put(46, 19, "b")
	cv.put(58, 19, "c")
	cv.barrel(60, 20)
	cv.put(66, 19, "d")
	cv.put(74, 19, "a")
	for c, prop in ((12, "tree_big"), (22, "bush_big"), (30, "tree_small"), (40, "tree_big"),
			(50, "bush_wide"), (58, "tree_small"), (66, "tree_big")):
		cv.prop(prop, c, 13)
	cv.put(36, 4, "e")
	cv.put(62, 4, "e")
	return cv


def boss_room():
	"""[选] 第 10 段「Boss 区」。一整片平地（Boss A 站在地上，冲撞和跳跃都不能碰到坑），
	头顶几块单向台子：躲它的导弹扇形、从高处往下打。Boss 是终点。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((8, 15), (30, 37), (52, 59), (70, 77)):
		cv.floor(c0, c1, 16, "=")
	for c0, c1 in ((18, 25), (40, 47), (60, 67)):
		cv.floor(c0, c1, 12, "=")
	cv.put(6, 19, "a")
	cv.put(20, 11, "c")
	cv.put(60, 19, "B")
	cv.fill(2, 3, 12, 19, "!")
	cv.fill(76, 77, 10, 19, "!")
	cv.prop("tree_big", 28, 20)
	cv.prop("fountain", 48, 20)
	for c, prop in ((12, "bush_big"), (24, "bench"), (36, "tree_small"), (42, "bush_wide"),
			(56, "rock_big"), (66, "tree_small"), (72, "bench")):
		cv.prop(prop, c, 20)
	return cv


SEGMENTS = [park, terraces, burrow, chasm, fortress, trench, islands, crossfire, tunnel, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
