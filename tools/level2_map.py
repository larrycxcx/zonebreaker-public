"""第二关（工业区）的分层版：一段一段画，`map_canvas.stitch()` 拼成一整关。

2026-10 按用户的示意图重做：画面还是连续横向卷动，但每一段都**分层**（上层 / 中层 / 地面，
层高 96 以上跳不上去，只能走梯子或缺口），有时得**绕路**。

用户看过前两段之后定的几条（2026-10）：
- **只有一个出口**（最后的 Boss）。十段里七段是**必须绕路**的（标 [绕]），三段是**上下两条路随便挑**的（标 [选]）。
- **敌人要多、要摆得合理**：会冲的（2-B 冲撞、2-F 自爆、2-A 落地就冲、2-D 看见就冲）只放在两头堵死的路上，
  **路的尽头不许是坑**（`map_build.check` 的 `chasers` 查这条：之前有冲刺的敌人还没冲到玩家跟前就自己掉坑里了）；
  上下分层的地方多放会斜射的 2-C。每一屏至少 4 个（`MIN_ENEMIES`）。
- **画面要满**：多摆小物件、障碍、机关（油桶、可打爆的箱子、传送带、液压机、闸门），不要大片空地。

字母表：a 2-A（吊在画面顶上、走到脚下砸下来）、b 2-B（冲撞）、c 2-C（枪手，会斜射）、d 2-D（锤子兵）、
e 2-E（直升机，飞的）、f 2-F（自爆机）、B Boss。行号：上层地板第 7 行、中层第 13 行、地面第 20 行；
敌人写在**脚下那一行的上一行**。
"""

from map_canvas import Canvas, from_png, stitch

LETTERS = {"a": "2_a", "b": "2_b", "c": "2_c", "d": "2_d", "e": "2_e", "f": "2_f", "boss": "2_boss"}
FLOATING = {"2_e", "2_boss"}
HANGING = {"2_a"}
## 会冲过来的：它们脚下那条路两头不许是坑
CHASERS = {"2_a", "2_b", "2_d", "2_f"}
MIN_ENEMIES = 4


def yard():
	"""[绕] 第 1 段「厂区门口」。
	第一屏露天、不放敌人：两根烟囱、两层钢梁走道（教你跳上去）。
	第二屏是两层的厂房 A：一楼从门口进去，**一楼走到头是墙**，得顺梯子爬上二楼；
	二楼的地板是一条**往回带的传送带**，自爆机顺着它冲过来。"""
	cv = Canvas(80)
	cv.ground(0, 39)
	cv.ground(40, 79, "%")
	cv.put(3, 19, "@")
	cv.fill(8, 9, 10, 19, "!")
	cv.fill(32, 33, 12, 19, "!")
	cv.floor(14, 24, 16, ":")
	cv.floor(20, 28, 12, ":")
	cv.prop("barrel_rust", 11, 20)
	cv.prop("box", 26, 20)
	cv.prop("sign", 36, 20)
	cv.prop("flag", 30, 12)
	# 厂房 A：屋顶第 7 行、二楼第 13 行；左外墙下面那 4 格是门，一楼尽头（78~79 列）是墙
	cv.floor(38, 79, 7)
	cv.fill(40, 41, 8, 15)
	cv.floor(42, 79, 13)
	cv.belt(62, 76, 13, -1)
	cv.fill(78, 79, 14, 19)
	cv.ladder(56, 13, 20)
	cv.crates(45, 20, 1)
	cv.put(50, 19, "d")
	cv.put(66, 19, "b")
	cv.put(74, 19, "c")
	cv.barrel(72, 20)
	cv.put(62, 19, "c")
	cv.prop("screen", 42, 11)            # 二楼墙上的监控屏（会动）
	cv.put(46, 12, "c")
	cv.put(74, 12, "f")
	cv.barrel(70, 13)
	# 屋顶：钢架箱、栏杆
	cv.fill(56, 59, 5, 6, "X")
	cv.prop("barrel_rust", 66, 7)
	cv.rail(62, 76, 7)
	cv.prop("board", 62, 18)
	cv.prop("locker", 48, 11)
	cv.pipe([(22, 8), (38, 8)])
	cv.sign(1, 30, 8)
	cv.pipe([(21, 4), (39, 4)])
	cv.sign(2, 33, 4)
	return cv


def gantry():
	"""[绕] 第 2 段「钢架」。厂房 A 的后半截：二楼出口是**闸门**，一楼被机器堵死。
	出来是一片沉降池，**底下全是坑**，只能走钢梁；钢梁上方还有一层更高的，枪手站在上面往下斜着打，
	吊着的 2-A 砸在钢梁上、直升机在旁边扔炸弹。钢梁走到头顺梯子下地面。"""
	cv = Canvas(80)
	cv.floor(0, 25, 7)
	cv.floor(0, 23, 13)
	cv.fill(0, 21, 14, 19, "X")         # 一楼被机器堵死
	cv.fill(22, 23, 14, 19)
	cv.ground(0, 23)
	cv.floor(22, 23, 8)
	cv.put(22, 9, "G")
	cv.put(8, 12, "c")
	cv.put(14, 12, "b")
	cv.barrel(10, 13)
	cv.prop("locker", 4, 11)            # 挂在墙上
	cv.prop("board", 16, 11)
	# 沉降池：24~55 列底下是坑；池子里立着几根管子
	cv.fill(30, 31, 15, 22, "!")
	cv.fill(44, 45, 14, 22, "!")
	cv.fill(52, 53, 16, 22, "!")
	cv.floor(24, 61, 13, ":")
	cv.floor(34, 46, 9, ":")            # 更高的一层：枪手站在上面往下打
	cv.rail(26, 32, 13)
	cv.put(40, 8, "c")
	cv.put(36, 0, "a")
	cv.put(48, 0, "a")
	cv.put(30, 4, "e")
	cv.put(54, 5, "e")
	cv.put(66, 5, "e")
	# 对岸：池边一道矮沿（冲过来的不会掉进池子），梯子落在沿后面
	cv.ground(56, 79)
	cv.fill(56, 57, 18, 19)
	cv.ladder(58, 13, 20)
	cv.crates(64, 20, 2)
	cv.put(70, 19, "d")
	cv.put(76, 19, "c")
	cv.barrel(74, 20)
	cv.prop("warning", 61, 20)
	return cv


def ambush():
	"""[选] 第 3 段「伏击」。上面一条断成三截的钢梁（跳得过去），下面是地面，**走哪条都行**：
	上面有三个枪手往下斜着打，下面有冲撞的、自爆的，钢梁的断口上方吊着两只 2-A，从地面走就会被砸。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(2, 24, 13, ":")
	cv.ladder(4, 13, 20)
	cv.floor(29, 50, 13, ":")
	cv.floor(55, 75, 13, ":")
	cv.ladder(72, 13, 20)
	cv.put(12, 19, "d")
	cv.put(18, 12, "c")
	cv.put(26, 0, "a")
	cv.put(36, 4, "e")
	cv.put(40, 19, "b")
	cv.put(44, 12, "c")
	cv.put(52, 0, "a")
	cv.put(64, 19, "f")
	cv.barrel(62, 20)
	cv.barrel(66, 20)
	cv.put(70, 12, "c")
	cv.put(62, 3, "e")
	cv.crates(32, 20, 1)
	cv.crates(48, 20, 2)
	cv.fill(22, 23, 14, 19, "!")
	cv.fill(58, 59, 14, 19, "!")
	cv.rail(6, 16, 13)
	cv.rail(58, 68, 13)
	return cv


def press_hall():
	"""[绕] 第 4 段「冲压车间」。一楼的左半间走到头是墙，梯子上二楼：二楼一排三台液压机，
	脚下还是一条**往回带的传送带**——要算好节奏往前挤。过了液压机地板上有个洞，掉进一楼的右半间，
	那里有一整摞**可打爆的箱子**把路堵死，打烂了才出得去。"""
	cv = Canvas(80)
	cv.floor(0, 79, 6)                  # 车间屋顶
	cv.fill(0, 1, 7, 15)                # 左外墙，下面那 4 格是门
	cv.fill(78, 79, 7, 15)              # 右外墙，同样
	cv.floor(0, 79, 13)
	cv.ground(0, 79)
	cv.fill(30, 31, 14, 19)             # 一楼左半间到头
	cv.ladder(24, 13, 20)
	cv.belt(32, 52, 13, -1)
	cv.put(34, 9, "P")
	cv.put(42, 9, "P")
	cv.put(50, 9, "P")
	cv.clear(58, 59, 13, 13)            # 二楼地板上的洞
	cv.crates(70, 20, 4)                # 一楼右半间：一整摞箱子堵死
	cv.put(8, 19, "c")
	cv.put(16, 19, "b")
	cv.put(22, 19, "d")
	cv.barrel(10, 20)
	cv.put(38, 19, "c")
	cv.barrel(40, 20)
	cv.put(56, 19, "d")
	cv.put(54, 12, "c")
	cv.put(66, 12, "c")
	cv.put(72, 12, "c")
	cv.prop("screen", 56, 18)
	cv.barrel(68, 13)
	cv.put(74, 19, "f")
	cv.prop("board", 12, 18)
	cv.prop("locker", 62, 11)
	cv.pipe([(2, 4), (14, 4)])
	cv.sign(3, 8, 4)
	cv.pipe([(17, 8), (34, 8)])
	cv.sign(4, 26, 8)
	cv.fill(56, 59, 4, 5, "X")          # 屋顶上的箱子
	cv.rail(4, 20, 6)
	return cv


def settling():
	"""[绕] 第 5 段「沉降池」。地面断成三截，坑宽 12 格跳不过去，**只能爬上高处的钢梁**，
	一截一截跳过去。中间那个小岛可以下去（油桶边上站着枪手），再从岛上的梯子爬回来。
	两边坑沿都有一道矮沿：冲过来的敌人不会自己掉下去。"""
	cv = Canvas(80)
	cv.ground(0, 15)
	cv.fill(14, 15, 18, 19)
	cv.ground(28, 41)
	cv.ground(54, 79)
	cv.fill(54, 55, 18, 19)
	cv.floor(4, 22, 10, ":")
	cv.ladder(8, 10, 20)
	cv.floor(28, 36, 10, ":")
	cv.ladder(38, 10, 20)
	cv.floor(40, 50, 10, ":")
	cv.floor(55, 64, 10, ":")
	cv.fill(20, 21, 13, 22, "!")
	cv.fill(46, 47, 14, 22, "!")
	cv.put(18, 9, "c")
	cv.put(4, 19, "b")
	cv.put(20, 4, "e")
	cv.put(32, 19, "c")
	cv.barrel(30, 20)
	cv.put(34, 9, "c")
	cv.put(46, 9, "c")
	cv.put(48, 5, "e")
	cv.put(60, 9, "c")
	cv.put(70, 19, "d")
	cv.put(76, 19, "b")
	cv.barrel(66, 20)
	cv.crates(62, 20, 1)
	cv.rail(5, 13, 10)
	cv.rail(41, 49, 10)
	cv.prop("warning", 12, 20)
	cv.prop("warning", 56, 20)
	return cv


def alarm():
	"""[选] 第 6 段「警报区」。一座长棚：**棚里**是自爆机和冲撞的，身边堆着油桶（打桶连它们一起炸）；
	**棚顶**是枪手和直升机，顺棚外的梯子上去。两条路在棚子另一头会合。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.ladder(2, 9, 20)
	cv.floor(4, 71, 9)
	cv.fill(4, 5, 10, 15)
	cv.fill(70, 71, 10, 15)
	cv.put(24, 19, "f")
	cv.barrel(22, 20)
	cv.barrel(26, 20)
	cv.put(38, 19, "b")
	cv.crates(32, 20, 1)
	cv.put(50, 19, "f")
	cv.barrel(48, 20)
	cv.barrel(52, 20)
	cv.crates(60, 20, 2)
	cv.fill(20, 21, 7, 8, "X")
	cv.fill(56, 57, 7, 8, "X")
	cv.put(16, 8, "c")
	cv.put(44, 8, "c")
	cv.put(34, 8, "c")
	cv.put(64, 8, "c")
	cv.put(30, 3, "e")
	cv.put(76, 19, "d")
	cv.pipe([(4, 6), (34, 6)])
	cv.sign(5, 18, 6)
	cv.rail(8, 18, 9)
	cv.rail(46, 54, 9)
	return cv


def heights():
	"""[绕] 第 7 段「高处」。地面被一座高塔挡死，得**两段梯子**爬上塔顶：先上中间那块平台（上面的枪手往下斜着打），
	再上塔顶。翻过去顺着两级钢梁下来，直升机在半空守着。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(38, 43, 6, 19)              # 塔
	cv.floor(20, 46, 6)
	cv.floor(8, 24, 13)
	cv.ladder(12, 13, 20)
	cv.ladder(22, 6, 13)
	cv.floor(47, 56, 10, ":")
	cv.floor(56, 64, 14, ":")
	cv.put(6, 19, "d")
	cv.put(16, 12, "c")
	cv.put(32, 5, "c")
	cv.put(42, 5, "c")
	cv.put(28, 2, "e")
	cv.put(52, 3, "e")
	cv.put(52, 9, "c")
	cv.put(66, 19, "c")
	cv.barrel(68, 20)
	cv.put(72, 19, "b")
	cv.fill(28, 29, 4, 5, "X")
	cv.crates(30, 20, 2)
	cv.rail(26, 36, 6)
	cv.pipe([(5, 7), (11, 7)])
	cv.sign(6, 8, 7)
	return cv


def crossfire():
	"""[绕] 第 8 段「三层交叉火力」。示意图那一屏的放大版：一楼左半间到头是墙，梯子上二楼；
	二楼过一台液压机后也被墙挡住，地板上的洞掉回一楼右半间（单向的台子上站着往上下斜射的枪手），
	再从梯子爬回二楼的右半截。"""
	cv = Canvas(80)
	cv.floor(0, 79, 7)
	cv.floor(0, 79, 13)
	cv.ground(0, 79)
	cv.fill(31, 32, 14, 19)
	cv.ladder(26, 13, 20)
	cv.put(44, 9, "P")
	cv.fill(56, 57, 8, 12)
	cv.clear(50, 51, 13, 13)
	cv.floor(40, 46, 17, "=")
	cv.ladder(66, 13, 20)
	cv.fill(78, 79, 14, 19)             # 一楼右半间到头：只能爬回二楼
	cv.put(14, 19, "b")
	cv.put(8, 19, "c")
	cv.prop("screen", 40, 11)
	cv.put(6, 12, "c")
	cv.put(20, 12, "d")
	cv.put(36, 12, "c")
	cv.barrel(38, 13)
	cv.put(48, 12, "c")
	cv.put(42, 16, "c")
	cv.put(60, 19, "c")
	cv.barrel(62, 20)
	cv.put(72, 19, "d")
	cv.put(74, 12, "f")
	cv.barrel(70, 13)
	cv.crates(36, 20, 1)
	cv.fill(10, 13, 5, 6, "X")
	cv.fill(60, 61, 5, 6, "X")
	cv.rail(20, 34, 7)
	cv.pipe([(2, 4), (13, 4)])
	cv.sign(7, 7, 4)
	cv.pipe([(17, 8), (38, 8)])
	cv.sign(8, 30, 8)
	return cv


def narrow():
	"""[绕] 第 9 段「窄道」。二楼走到头，梯子下到一条又低又长的通道里：一条道走到底，
	冲撞的、自爆的、锤子兵迎面过来，**两摞箱子堵着路**（打烂才过得去），两台液压机，
	脚下的传送带有往回带的。"""
	cv = Canvas(80)
	cv.floor(0, 73, 7)
	cv.floor(0, 9, 13)
	# 通道顶上是一间进不去的机房（两头封死）：从外面看得见里面的墙、管子、机器，不是一整块平的
	cv.floor(10, 73, 13)
	cv.floor(10, 73, 14)
	cv.fill(10, 11, 8, 12)
	cv.fill(72, 73, 8, 12)
	cv.fill(24, 27, 10, 12, "X")
	cv.fill(44, 45, 11, 12, "X")
	cv.fill(58, 61, 11, 12, "X")
	cv.prop("board", 34, 11)
	cv.prop("locker", 52, 11)
	cv.ground(0, 79)
	cv.ladder(4, 13, 20)
	cv.belt(14, 24, 20, -1)
	cv.crates(26, 20, 3)
	cv.belt(32, 46, 20, -1)
	cv.put(38, 16, "P")
	cv.crates(52, 20, 3)
	cv.belt(56, 66, 20, 1)
	cv.put(62, 16, "P")
	cv.put(6, 12, "c")
	cv.put(12, 19, "d")
	cv.put(18, 19, "b")
	cv.put(32, 19, "f")
	cv.barrel(30, 20)
	cv.put(46, 19, "b")
	cv.put(58, 19, "f")
	cv.barrel(56, 20)
	cv.put(68, 19, "d")
	cv.put(76, 19, "b")
	cv.fill(30, 33, 5, 6, "X")
	cv.fill(50, 51, 5, 6, "X")
	cv.rail(36, 46, 7)
	cv.pipe([(5, 8), (36, 8)])
	cv.sign(9, 20, 8)
	cv.pipe([(7, 5), (34, 5)])
	return cv


def boss_room():
	"""[选] 第 10 段「Boss 区」。一大片空地 + 八块单向台子（两块架到 Boss 的高度——它飘在空中，
	要跳上去才打得着）。Boss 是终点。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((6, 13), (26, 33), (46, 53), (66, 73)):
		cv.floor(c0, c1, 16, "=")
	for c0, c1 in ((16, 23), (36, 43), (56, 63)):
		cv.floor(c0, c1, 12, "=")
	cv.floor(28, 33, 8, "=")
	cv.floor(48, 53, 8, "=")
	cv.put(10, 15, "c")
	cv.put(20, 11, "c")
	cv.put(58, 10, "B")
	cv.fill(2, 3, 12, 19, "!")
	cv.fill(76, 77, 10, 19, "!")
	cv.prop("flag", 30, 8)
	cv.prop("warning", 40, 20)
	return cv


SEGMENTS = [yard, gantry, ambush, press_hall, settling, alarm, heights, crossfire, narrow, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
