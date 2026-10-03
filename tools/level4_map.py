"""第四关（地下室，**纵向往上爬**）的格子地图版（2026-10 用户：「第四关也要按之前的要求重新设计——
不同的路线、复杂的结构、更多细节贴图」）。

一整根竖井：**40 格宽（一屏）、450 格高（20 屏）**，两侧各 2 格实心岩墙，里面是第 2~37 列。
十段，每段 45 格（两屏），**从下往上**数：第 1 段是出生那一段，第 10 段最上面是 Boss 区（地板在第 20 行 = y 320）。
每段函数拿到 `top`（这一段最上面那一行在整张图里是第几行），段里用「段内行号」0~44 画（44 是这一段最底下）。

**段与段怎么接**：每段的出口是段内第 1 行的一块台子，下一段的入口是它段内第 42 行的一条单向台子——
两者正好隔 4 行，一跳上得去。一段 45 行、一跳最多 4 行，所以段里往上那一串台子**快到顶时要有几步是 3 行**
（…→10→7→4→1），不然最后一步是 5 行、跳不上去（第一版就这么卡在了第二段顶上）。

和前三关同一套原则：
- 十段里七段**必须绕路**（标 [绕]），三段**两条路随便挑**（标 [选]），只有一个出口（Boss）。
- 往上爬的关，「绕路」是**横着绕**：实心楼板只在一头留口子 / 架梯子，得走到另一头才上得去；
  画面只往上卷（`only_up`），往下走最多十来格，所以每段都往上走、不往回走。
- 敌人多、摆得合理：会斜射的西装男 4-C、蜘蛛炮台 4-E 守在楼层上，无人机 4-D **贴着两侧的墙**
  （它横向不动，摆在中间挡路），从下面追上来的 4-A 放在每一段的下半截。
- 画面要满：砖墙房间、竖着的管道、霓虹招牌、集装箱、蒸汽，油桶和可打爆的箱子。

字母表：a 4-A（打手，从下面追上来）、b 4-B（猫耳女，平台守卫）、c 4-C（西装男，三向枪手）、
d 4-D（无人机，贴着你的高度飞，飞的）、e 4-E（蜘蛛炮台，矮）、f 4-F（骷髅衫，把人抡下平台）、B 骷髅头 Boss。
"""

from map_canvas import Canvas

LETTERS = {"a": "4_a", "b": "4_b", "c": "4_c", "d": "4_d", "e": "4_e", "f": "4_f", "boss": "4_boss"}
FLOATING = {"4_d", "4_boss"}
HANGING = set()
CHASERS = {"4_a"}
MIN_ENEMIES = 4
## 骷髅头摆在格子里的高度：第 17 行再往下 16 = y 288（激光出口在它下面 16，正对站在第 20 行地板上的人的身体中心）
FLOAT_AT = {"4_boss": 16.0}

WIDTH = 40
SEG = 45
SEGMENTS_N = 10
HEIGHT = SEG * SEGMENTS_N
## 一整段都是一路单向台子时用的那串行号：从入口（42）往上每次 4 行，快到顶换成 3 行，最后到出口（1）的下面 3 行
CLIMB = [38, 34, 30, 26, 22, 18, 14, 10, 7, 4]


class Seg:
	"""一段：把「段内行号」换成整张图的行号，其余照 `Canvas` 的用法。"""

	def __init__(self, cv, top):
		self.cv, self.top = cv, top

	def ledge(self, c0, c1, row, ch="="):
		self.cv.floor(c0, c1, self.top + row, ch)

	def slab(self, c0, c1, row, ch="#"):
		self.cv.floor(c0, c1, self.top + row, ch)

	def fill(self, c0, c1, r0, r1, ch="#"):
		self.cv.fill(c0, c1, self.top + r0, self.top + r1, ch)

	def ladder(self, c, top, bottom):
		self.cv.ladder(c, self.top + top, self.top + bottom)

	def put(self, c, row, ch):
		self.cv.put(c, self.top + row, ch)

	def crates(self, c, row, count=1):
		self.cv.crates(c, self.top + row, count)

	def barrel(self, c, row):
		self.cv.barrel(c, self.top + row)

	def prop(self, name, c, row):
		self.cv.prop(name, c, self.top + row)

	def entry(self):
		"""入口：段内第 42 行一条整宽的单向台子（下一段的出口台子在它下面 4 行）。"""
		self.ledge(2, 37, 42)


def sump(s):
	"""[绕] 第 1 段「集水坑」（出生）。第一屏不放敌人：几级台子教你往上跳。
	头顶一整块实心楼板，**只在右头架了一架梯子**——第一次爬梯子。楼板上面那一屏开始有敌人。"""
	s.cv.ground(2, 37)
	s.put(4, 41, "@")
	s.ledge(8, 15, 38)
	s.ledge(16, 23, 34)
	s.ledge(24, 31, 30)
	s.ledge(28, 36, 26)
	s.slab(2, 37, 20)
	s.slab(2, 37, 21)
	s.ladder(32, 20, 26)
	s.ledge(4, 12, 16)
	s.ledge(12, 20, 12)
	s.ledge(20, 28, 8)
	s.ledge(26, 34, 4)
	s.ledge(30, 37, 1)
	s.put(16, 11, "c")
	s.put(24, 7, "c")
	s.put(36, 9, "d")
	s.put(27, 3, "e")
	s.put(33, 3, "e")
	s.prop("smoke", 20, 42)
	s.prop("container", 30, 42)
	s.prop("sign_hotel", 6, 30)
	s.fill(14, 15, 22, 33, "!")


def twin_shafts(s):
	"""[选] 第 2 段「双井」。中间一道墙把竖井分成两半：**左边**是一层层的实心台子，梯子一架接一架
	（台子上站着守卫和抡人的）；**右边**是一路单向台子，枪手和无人机守着。两边在顶上会合。"""
	s.entry()
	s.fill(19, 20, 4, 37)                # 中间那道墙（底下留 4 行：两边都走得进去）
	# 左井：实心台子 + 梯子
	s.slab(6, 17, 34)
	s.slab(2, 14, 26)
	s.slab(6, 17, 18)
	s.slab(2, 14, 10)
	s.ladder(4, 34, 42)
	s.ladder(15, 26, 34)
	s.ladder(4, 18, 26)
	s.ladder(15, 10, 18)
	s.ledge(8, 18, 7)
	s.ledge(6, 14, 4)
	# 右井：单向台子之字形往上
	for row, (c0, c1) in zip(CLIMB, [(22, 30), (28, 36)] * 5):
		s.ledge(c0, c1, row)
	s.ledge(2, 37, 1)
	s.put(10, 33, "e")
	s.put(8, 25, "b")
	s.put(10, 17, "e")
	s.put(8, 9, "f")
	s.barrel(11, 10)
	s.put(26, 37, "c")
	s.put(36, 28, "d")
	s.put(32, 17, "c")
	s.barrel(34, 18)
	s.put(26, 13, "e")
	s.put(36, 8, "d")
	s.fill(2, 3, 35, 41, "!")
	s.prop("sign_poker", 22, 26)
	s.prop("pipe_tall", 12, 34)


def boiler_room(s):
	"""[绕] 第 3 段「锅炉房」。一间矮屋子：从左边楼板的口子钻进去，屋里打手、守卫、蜘蛛炮台，
	**右头的梯子前面一整摞箱子堵着**，打烂了才爬得出去。屋顶上面一路之字形往上。"""
	s.entry()
	s.ledge(2, 5, 39)                    # 只在楼板的口子底下，不伸进楼板底下（那儿只剩 32 高的缝）
	s.slab(6, 37, 36)                    # 屋子的地板（左头 2~5 列是口子）
	s.fill(2, 37, 26, 28)                # 屋顶
	s.ladder(34, 26, 36)
	s.crates(30, 36, 4)                  # 梯子前面那一摞
	s.put(20, 41, "c")
	s.put(12, 35, "a")
	s.put(20, 35, "b")
	s.barrel(22, 36)
	s.put(26, 35, "e")
	s.prop("smoke", 8, 36)
	s.prop("pipe_bend", 16, 36)
	s.ledge(24, 32, 22)
	s.ledge(16, 24, 18)
	s.ledge(8, 16, 14)
	s.ledge(2, 10, 10)
	s.ledge(8, 20, 7)
	s.ledge(14, 26, 4)
	s.ledge(14, 37, 1)
	s.put(28, 21, "c")
	s.put(3, 16, "d")
	s.put(12, 13, "f")
	s.put(16, 6, "e")
	s.put(36, 12, "d")
	s.prop("sign_carre", 28, 14)


def vents(s):
	"""[绕] 第 4 段「通风井」。四层实心楼板，**梯子一层在右、一层在左**，只能之字形往上爬；
	每一层楼板上都站着人，身边堆着油桶和箱子。"""
	s.entry()
	s.slab(2, 37, 36)
	s.slab(2, 37, 28)
	s.slab(2, 37, 20)
	s.slab(2, 37, 12)
	s.ladder(34, 36, 42)
	s.ladder(4, 28, 36)
	s.ladder(34, 20, 28)
	s.ladder(4, 12, 20)
	s.ledge(18, 28, 8)
	s.ledge(8, 18, 4)
	s.ledge(2, 12, 1)                    # 出口在左边：上面那段（货梯井）只有左边那条缝通着
	s.put(16, 35, "b")
	s.put(24, 35, "e")
	s.barrel(18, 36)
	s.put(20, 27, "f")
	s.put(10, 27, "c")
	s.crates(14, 28, 1)
	s.put(16, 19, "e")
	s.put(26, 19, "a")
	s.barrel(28, 20)
	s.put(24, 11, "c")
	s.put(14, 11, "b")
	s.crates(30, 12, 1)
	s.put(3, 5, "d")
	s.prop("container_moss", 30, 28)
	s.prop("smoke", 10, 20)
	s.prop("unit", 8, 12)


def lift_shaft(s):
	"""[绕] 第 5 段「货梯井」。竖井正中码着一大垛集装箱，**右边那条缝底下是封死的**：
	只能顺左边一路跳上去、翻过集装箱垛顶，再从右边的缝往上爬。右边缝里的炮台和枪手隔着缝打你。"""
	s.entry()
	s.fill(12, 27, 10, 41, "X")          # 中间那一垛
	s.fill(28, 37, 30, 41)               # 右边缝的底下封死
	for row, (c0, c1) in zip(range(38, 9, -4), [(2, 7), (6, 11)] * 4):
		s.ledge(c0, c1, row)
	s.ledge(28, 33, 26)
	s.ledge(32, 37, 22)
	s.ledge(28, 33, 18)
	s.ledge(32, 37, 14)
	s.ledge(28, 33, 10)
	s.ledge(26, 37, 7)
	s.ledge(20, 30, 4)
	s.ledge(14, 30, 1)
	s.put(4, 37, "a")
	s.put(30, 29, "e")
	s.put(34, 21, "c")
	s.put(30, 17, "e")
	s.put(4, 21, "c")
	s.put(8, 33, "c")
	s.put(4, 29, "f")
	s.put(36, 10, "d")
	s.put(20, 9, "f")
	s.put(30, 6, "c")
	s.barrel(33, 30)
	s.prop("crane", 18, 10)
	s.prop("sign_hotel", 28, 34)


def casino(s):
	"""[绕] 第 6 段「赌场后门」。一进来是一条又低又长的走廊，**一整摞箱子把走廊拦腰堵住**，
	打烂了才走得到右头的梯子；上面是挂着霓虹招牌的大厅，平台上守卫站岗。"""
	s.ledge(2, 37, 42)                   # 走廊的地板（从下面跳得上来）
	s.fill(2, 37, 34, 36)                # 走廊顶
	s.ladder(34, 34, 42)
	s.crates(20, 42, 3)
	s.put(8, 41, "e")
	s.put(14, 41, "b")
	s.put(26, 41, "a")
	s.put(30, 41, "c")
	s.barrel(28, 42)
	s.ledge(24, 32, 30)
	s.ledge(14, 22, 26)
	s.ledge(4, 12, 22)
	s.slab(10, 24, 18, ":")
	s.ledge(20, 30, 14)
	s.ledge(28, 36, 10)
	s.ledge(18, 28, 7)
	s.ledge(10, 20, 4)
	s.ledge(6, 20, 1)
	s.put(18, 17, "b")
	s.put(8, 21, "c")
	s.put(36, 20, "d")
	s.put(24, 13, "f")
	s.put(32, 9, "e")
	s.put(3, 8, "d")
	s.prop("sign_poker", 4, 30)
	s.prop("sign_carre", 26, 22)
	s.prop("sign_hotel", 30, 6)


def subway(s):
	"""[选] 第 7 段「地铁检修道」。**左边**贴着墙两架长梯子，一口气爬上去（爬梯子时不能开枪）；
	**右边**一路单向台子，枪手、守卫和两架无人机。两条路在顶上会合。"""
	s.entry()
	s.slab(4, 12, 22)
	s.ladder(2, 22, 42)
	s.ladder(2, 1, 22)
	for row, (c0, c1) in zip(CLIMB, [(20, 28), (27, 35)] * 5):
		s.ledge(c0, c1, row)
	s.ledge(4, 37, 1)
	s.put(8, 21, "e")
	s.put(24, 37, "c")
	s.put(21, 37, "e")
	s.put(36, 30, "d")
	s.put(30, 25, "c")
	s.put(24, 21, "b")
	s.put(24, 13, "b")
	s.put(36, 12, "d")
	s.put(24, 6, "e")
	s.fill(16, 17, 6, 41, "!")
	s.prop("smoke", 8, 22)
	s.prop("container", 22, 42)


def sewer(s):
	"""[绕] 第 8 段「下水道」。一整块实心的岩层，**只有正中一架梯子**；爬上去是一条低矮的暗渠，
	左边一摞箱子堵着往上的那架梯子，右边是死路（守卫和油桶）。暗渠顶上再一路往上。"""
	s.entry()
	s.ledge(2, 10, 38)
	s.ledge(6, 16, 34)
	s.ledge(14, 26, 30)
	s.fill(2, 37, 24, 26)                # 岩层
	s.fill(2, 37, 16, 18)                # 暗渠顶
	s.ladder(19, 24, 30)
	s.ladder(3, 16, 24)
	s.crates(12, 24, 3)
	s.put(6, 37, "a")
	s.put(12, 33, "c")
	s.put(22, 29, "e")
	s.put(8, 23, "b")
	s.put(16, 23, "e")
	s.put(30, 23, "f")
	s.barrel(28, 24)
	s.barrel(33, 24)
	s.ledge(4, 12, 12)
	s.ledge(10, 20, 8)
	s.ledge(18, 30, 4)
	s.ledge(24, 37, 1)
	s.put(8, 11, "c")
	s.put(36, 8, "d")
	s.put(14, 7, "f")
	s.put(24, 3, "e")
	s.prop("grate", 24, 30)
	s.prop("pipe_moss", 30, 42)


def last_climb(s):
	"""[绕] 第 9 段「最后的爬升」。两层楼板，梯子一右一左；下面的打手一路追上来，
	每层都有枪手和炮台，最后几层台子直通 Boss 区底下。"""
	s.entry()
	s.slab(2, 37, 32)
	s.slab(2, 37, 18)
	s.ladder(34, 32, 42)
	s.ladder(4, 18, 32)
	s.ledge(8, 18, 38)
	s.put(8, 41, "a")
	s.put(14, 37, "a")
	s.put(24, 41, "c")
	s.put(14, 31, "c")
	s.put(22, 31, "e")
	s.put(30, 31, "b")
	s.barrel(28, 32)
	s.crates(10, 32, 1)
	s.ledge(10, 20, 14)
	s.ledge(18, 28, 10)
	s.ledge(26, 34, 7)
	s.ledge(18, 28, 4)
	s.ledge(20, 37, 1)
	s.put(26, 17, "c")
	s.put(16, 17, "f")
	s.put(3, 12, "d")
	s.put(22, 9, "e")
	s.put(36, 4, "d")
	s.prop("smoke", 26, 18)
	s.prop("container_moss", 6, 32)


def boss_room(s):
	"""[选] 第 10 段：下半截是 Boss 区底下那几层台子，上半截是 Boss 区——地板在第 20 行（y 320），
	地板上方两块高台、一块更高的（躲激光：换一层）。骷髅头飘在右侧。"""
	s.entry()
	s.ledge(4, 14, 38)
	s.ledge(12, 22, 34)
	s.ledge(20, 30, 30)
	s.ledge(26, 36, 26)
	s.ledge(14, 24, 24)
	s.slab(2, 37, 20, ":")               # Boss 区的地板（单向：从下面跳得上来）
	s.ledge(4, 13, 16)
	s.ledge(26, 35, 16)
	s.ledge(14, 25, 12)
	s.put(8, 37, "c")
	s.put(16, 33, "e")
	s.put(34, 25, "c")
	s.put(34, 17, "B")
	s.prop("sign_carre", 18, 20)
	s.fill(2, 3, 4, 19, "!")
	s.fill(36, 37, 4, 15, "!")


SEGMENTS = [sump, twin_shafts, boiler_room, vents, lift_shaft, casino, subway, sewer, last_climb, boss_room]


def assemble():
	"""从下往上画：第 1 段在最底下。两侧的岩墙一直通到顶。"""
	cv = Canvas(WIDTH, HEIGHT)
	cv.fill(0, 1, 0, HEIGHT - 1)
	cv.fill(38, 39, 0, HEIGHT - 1)
	for i, make in enumerate(SEGMENTS):
		make(Seg(cv, HEIGHT - SEG * (i + 1)))
	return cv.rows(), cv.props, {"pipes": [], "signs": [], "rails": cv.rails}
