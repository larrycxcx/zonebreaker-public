"""第三关（酒吧街）的分层版：一段一段画，`map_canvas.stitch()` 拼成一整关。

和第一、二关同一套设计原则（2026-10 用户定的）：
- **只有一个出口**（最后的 Boss）。十段里七段**必须绕路**（标 [绕]），三段**两条路随便挑**（标 [选]）。
- **敌人多、摆得合理**：会冲的（3-A 突刺、3-C 跳劈、3-D 壮汉）只放在两头堵死的路上，路的尽头不许是坑；
  上下分层的地方多放会斜射的 3-B。每一屏至少 4 个（`MIN_ENEMIES`）。
- **画面要满**：街边一栋栋楼面（`facade_N`）、吧台酒柜吧凳酒桶、油桶、可打爆的箱子，不要大片空地。

酒吧街的「室内」就是楼里：头顶有楼板的地方铺灰砖墙（见 `map_build.THEMES["bar"]`）。
**楼面只摆在露天的街边**：它画在室内墙的上面，摆进楼里就把墙盖住了。

字母表：a 3-A（刀客，蓄一下急冲）、b 3-B（枪手，会斜射）、c 3-C（剑客，跳劈）、d 3-D（壮汉，正面减伤）、
e 3-E（鲨鱼机，贴地开枪——趴下躲不掉、只能跳）、f 3-F（炮车，打手雷）、B Boss 3（独轮机甲）。
行号：上层地板第 7 行、中层第 13 行、地面第 20 行；敌人写在**脚下那一行的上一行**。
"""

from map_canvas import Canvas, stitch

LETTERS = {"a": "3_a", "b": "3_b", "c": "3_c", "d": "3_d", "e": "3_e", "f": "3_f", "boss": "3_boss"}
FLOATING = set()
HANGING = set()
CHASERS = {"3_a", "3_c", "3_d"}
MIN_ENEMIES = 4


def street():
	"""[绕] 第 1 段「街口」。第一屏不放敌人：街边的楼、几块雨棚。
	第二屏一座两层的酒吧把街整个占住：从正门进一楼，**一楼走到头是墙**，顺梯子上二楼，
	二楼从后门出到雨棚上、跳回街上。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.put(3, 19, "@")
	cv.prop("facade_1", 2, 20)
	cv.prop("facade_3", 14, 20)
	cv.prop("facade_6", 22, 20)
	cv.prop("facade_2", 31, 20)
	cv.floor(10, 15, 15, "=")
	cv.floor(20, 26, 12, "=")
	# 酒吧：屋顶第 7 行，正门在左墙下面，右墙二楼那一截是后门
	cv.floor(42, 73, 7)
	cv.fill(44, 45, 8, 15, "%")
	cv.floor(46, 71, 13)
	cv.fill(70, 71, 8, 9, "%")
	cv.fill(70, 71, 14, 19, "%")
	cv.floor(72, 79, 13, "=")
	cv.ladder(64, 13, 20)
	cv.crates(56, 20, 1)
	cv.put(52, 19, "a")
	cv.put(60, 19, "e")
	cv.put(68, 19, "b")
	cv.put(50, 12, "b")
	cv.put(60, 12, "f")
	cv.barrel(62, 13)
	cv.put(76, 12, "b")
	cv.prop("counter", 47, 20)
	cv.prop("cabinet", 54, 13)
	cv.prop("sign2", 46, 7)
	return cv


def awnings():
	"""[选] 第 2 段「雨棚阶梯」。**上面**：一级级雨棚上到一条长长的阳台，三个枪手站在上面往下斜着打；
	**下面**：街上的刀客、鲨鱼机、剑客。两条路在另一头会合。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c, name in ((2, "facade_4"), (16, "facade_5"), (30, "facade_1"), (42, "facade_2"),
			(54, "facade_3"), (62, "facade_6"), (71, "facade_1")):
		cv.prop(name, c, 20)
	cv.floor(4, 10, 16, "=")
	cv.floor(12, 18, 12, "=")
	cv.floor(20, 60, 9, "=")
	cv.put(6, 15, "f")
	cv.put(16, 19, "a")
	cv.put(24, 8, "b")
	cv.put(34, 19, "e")
	cv.put(44, 8, "b")
	cv.put(56, 8, "b")
	cv.put(50, 19, "a")
	cv.barrel(48, 20)
	cv.barrel(52, 20)
	cv.put(66, 19, "c")
	cv.crates(40, 20, 1)
	return cv


def cellar():
	"""[绕] 第 3 段「地窖」。一间抬高的酒吧：门廊上梯子进去，酒吧里往右被墙挡住，
	**从地板的活板门掉进地窖**：鲨鱼机贴着地面打（只能跳）、一摞箱子堵着，打烂了顺梯子爬上露台出去。
	地窖临街那一面是拉下来的卷帘，从街上进不去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(3, 75, 13, 14)               # 酒吧的地板（也是地窖的顶）
	cv.fill(3, 4, 15, 19, "%")           # 地窖临街：卷帘拉着
	cv.fill(74, 75, 15, 19, "%")
	cv.floor(6, 49, 7)                   # 酒吧的屋顶（右半截是露台，露天）
	cv.fill(48, 49, 8, 12, "%")          # 酒吧里往右走到头
	cv.clear(40, 41, 13, 14)             # 活板门
	cv.ladder(1, 13, 20)
	cv.ladder(66, 13, 20)
	cv.crates(58, 20, 3)
	cv.put(12, 12, "b")
	cv.put(24, 12, "d")
	cv.put(18, 12, "b")
	cv.put(34, 12, "b")
	cv.put(20, 19, "e")
	cv.put(32, 19, "c")
	cv.put(54, 19, "e")
	cv.barrel(56, 20)
	cv.put(64, 19, "a")
	cv.put(60, 12, "b")
	cv.put(70, 12, "f")
	cv.barrel(68, 13)
	cv.prop("counter", 8, 13)
	cv.prop("cabinet2", 16, 13)
	cv.prop("counter2", 28, 13)
	cv.prop("sign", 52, 13)              # 露台上立着的霓虹招牌
	cv.prop("facade_6", 76, 20)
	return cv


def drains():
	"""[绕] 第 4 段「排水沟」。街面断成三截，两道沟都跳不过去：顺梯子上雨棚，
	一块一块跳过去；中间那截路面上守着鲨鱼机和炮车，可以下去也可以不下。"""
	cv = Canvas(80)
	cv.ground(0, 13)
	cv.fill(12, 13, 18, 19)
	cv.ground(30, 45)
	cv.ground(62, 79)
	cv.fill(62, 63, 18, 19)
	cv.floor(2, 18, 10, "=")
	cv.floor(22, 28, 9, "=")
	cv.floor(32, 40, 11, "=")
	cv.floor(44, 50, 9, "=")
	cv.floor(54, 60, 10, "=")
	cv.floor(64, 72, 12, "=")
	cv.ladder(6, 10, 20)
	cv.ladder(34, 11, 20)
	cv.fill(20, 21, 14, 22, "!")
	cv.fill(52, 53, 13, 22, "!")
	cv.put(3, 19, "f")
	cv.put(16, 9, "b")
	cv.put(26, 8, "b")
	cv.put(38, 19, "e")
	cv.barrel(36, 20)
	cv.put(42, 19, "f")
	cv.put(48, 8, "b")
	cv.put(58, 9, "b")
	cv.put(68, 11, "b")
	cv.put(70, 19, "c")
	cv.put(76, 19, "a")
	cv.prop("facade_3", 31, 20)
	cv.prop("facade_4", 66, 20)
	return cv


def brutes():
	"""[绕] 第 5 段「壮汉」。一家关了门的铺子：一楼卷帘拉着，梯子上二楼；
	二楼一条长厅，三个壮汉一个接一个压过来（正面打只掉一半血：绕背、跳过去、或者把手雷扔过它头顶），
	厅尽头地板上的洞掉进一楼后半间，从后门出去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(5, 73, 7)
	cv.floor(5, 73, 13)
	cv.fill(6, 7, 14, 19, "%")           # 一楼卷帘
	cv.fill(8, 47, 14, 19, "X")          # 一楼前半间堆满了货
	cv.fill(48, 49, 14, 19, "%")
	cv.fill(72, 73, 8, 15, "%")          # 后墙，下面 4 格是后门
	cv.clear(60, 61, 13, 13)
	cv.ladder(3, 13, 20)
	cv.put(14, 12, "b")
	cv.put(20, 12, "d")
	cv.put(28, 12, "b")
	cv.put(36, 12, "d")
	cv.barrel(38, 13)
	cv.put(52, 12, "d")
	cv.put(68, 12, "b")
	cv.put(56, 19, "e")
	cv.put(64, 19, "a")
	cv.crates(68, 20, 1)
	cv.prop("cabinet", 10, 13)
	cv.prop("counter", 44, 13)
	cv.prop("facade_6", 74, 20)
	return cv


def long_street():
	"""[选] 第 6 段「炮车长街」。**下面**街上两辆炮车往前打手雷、身边堆着油桶；
	**上面**一整排阳台，枪手和剑客守着。左头顺梯子上阳台，或者直接走街上。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c, name in ((0, "facade_2"), (11, "facade_5"), (24, "facade_4"), (37, "facade_1"),
			(48, "facade_5"), (61, "facade_2"), (71, "facade_3")):
		cv.prop(name, c, 20)
	cv.floor(4, 74, 10, "=")
	cv.ladder(2, 10, 20)
	cv.put(14, 9, "b")
	cv.put(20, 19, "f")
	cv.barrel(22, 20)
	cv.put(28, 19, "a")
	cv.put(34, 19, "e")
	cv.crates(40, 20, 1)
	cv.put(44, 9, "b")
	cv.put(50, 19, "f")
	cv.barrel(48, 20)
	cv.put(62, 9, "c")
	cv.put(58, 19, "e")
	cv.put(70, 19, "a")
	return cv


def rooftops():
	"""[绕] 第 7 段「屋顶」。街到这儿是死路，顺消防梯爬上屋顶，**一栋一栋跳过去**：
	楼与楼之间的窄巷是坑。楼里是空的店面，从窗口看得见里面。最后跳回街上。"""
	cv = Canvas(80)
	cv.ground(0, 9)
	cv.ground(71, 79)                    # 最后一栋旁边就是街，从屋顶边上掉下去正好落在街上
	for c0, c1, top in ((10, 24, 8), (30, 42, 6), (48, 58, 9), (64, 70, 10)):
		cv.floor(c0, c1, top)                        # 屋顶
		cv.fill(c0, c0 + 1, top + 1, 22, "%")        # 两边的墙
		cv.fill(c1 - 1, c1, top + 1, 22, "%")
		cv.fill(c0 + 2, c1 - 2, 20, 22)              # 楼里的地（进不去，只是看得见）
	cv.ladder(8, 8, 20)
	cv.fill(26, 27, 12, 22, "!")
	cv.fill(60, 61, 14, 22, "!")
	cv.put(16, 7, "b")
	cv.put(20, 7, "f")
	cv.put(34, 5, "e")
	cv.put(38, 5, "b")
	cv.put(52, 8, "b")
	cv.put(56, 8, "f")
	cv.put(68, 9, "b")
	cv.put(66, 9, "f")
	cv.put(78, 19, "a")
	cv.prop("counter", 14, 20)
	cv.prop("cabinet", 36, 20)
	cv.prop("keg", 52, 20)
	return cv


def hotel():
	"""[绕] 第 8 段「三层交叉火力」。一座旅馆：一楼前半间到头是墙，梯子上二楼；
	二楼有一截是木头的单向楼板，楼下的枪手往上斜着打得到你、你也打得到他；
	二楼走到一半被墙挡住，梯子上屋顶，从屋顶的洞掉回二楼后半截，再从二楼的洞掉进一楼后半间出去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(10, 79, 7)
	cv.fill(0, 79, 13, 14)
	cv.floor(6, 15, 13, ":")
	cv.clear(6, 15, 14, 14)
	cv.fill(24, 25, 15, 19, "%")
	cv.fill(50, 51, 8, 12, "%")
	cv.clear(62, 63, 7, 7)
	cv.clear(74, 75, 13, 14)
	cv.ladder(18, 13, 20)
	cv.ladder(44, 7, 13)
	cv.put(8, 19, "a")
	cv.put(14, 19, "b")
	cv.put(12, 12, "b")
	cv.put(30, 12, "d")
	cv.put(56, 6, "e")
	cv.put(66, 6, "b")
	cv.put(60, 12, "b")
	cv.barrel(62, 13)
	cv.put(70, 12, "f")
	cv.put(40, 19, "c")
	cv.put(56, 19, "e")
	cv.barrel(58, 20)
	cv.crates(66, 20, 1)
	cv.put(72, 19, "b")
	cv.fill(30, 31, 5, 6, "X")
	cv.prop("counter2", 34, 13)
	cv.prop("cabinet2", 26, 20)
	return cv


def alley():
	"""[绕] 第 9 段「后巷」。一条长长的骑楼底下，一条道走到底：刀客、壮汉迎面过来，
	鲨鱼机贴着地面打，**两摞箱子把路堵死**（打烂才过得去）。骑楼上面的楼上不去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 75, 13, 14)
	cv.fill(4, 7, 0, 12, "%")
	cv.crates(26, 20, 3)
	cv.crates(52, 20, 3)
	cv.put(10, 19, "e")
	cv.put(16, 19, "a")
	cv.put(22, 19, "d")
	cv.put(32, 19, "b")
	cv.barrel(34, 20)
	cv.put(40, 19, "a")
	cv.put(46, 19, "e")
	cv.put(50, 19, "c")
	cv.put(58, 19, "d")
	cv.barrel(60, 20)
	cv.put(66, 19, "b")
	cv.put(74, 19, "a")
	for c, name in ((8, "facade_4"), (21, "facade_2"), (32, "facade_6"), (41, "facade_5"),
			(54, "facade_1"), (65, "facade_3")):
		cv.prop(name, c, 13)
	return cv


def boss_room():
	"""[选] 第 10 段「Boss 区」。独轮机甲站在地上、来回滚、冲撞一下能滚三百多：
	它左右 600 以内**一整片实地、没有墙**（墙会挡住它的视线，它就什么都不做）。头顶几块雨棚。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((8, 14), (28, 34), (50, 56), (68, 74)):
		cv.floor(c0, c1, 16, "=")
	for c0, c1 in ((18, 24), (38, 44), (58, 64)):
		cv.floor(c0, c1, 12, "=")
	cv.put(2, 19, "b")
	cv.put(20, 11, "b")
	cv.put(44, 19, "B")
	for c, name in ((0, "facade_5"), (13, "facade_1"), (24, "facade_4"), (37, "facade_2"),
			(48, "facade_6"), (57, "facade_5"), (70, "facade_1")):
		cv.prop(name, c, 20)
	return cv


SEGMENTS = [street, awnings, cellar, drains, brutes, long_street, rooftops, hotel, alley, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
