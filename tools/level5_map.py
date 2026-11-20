"""第五关（实验室）的分层版：一段一段画，`map_canvas.stitch()` 拼成一整关。

和前几关同一套设计原则（2026-10 用户定的）：
- **只有一个出口**（最后的 Boss「生化舱」）。十段里七段**必须绕路**（标 [绕]），三段**两条路随便挑**（标 [选]）。
- **敌人多、摆得合理**：会冲的（5-A / 5-B 科学家变身以后、5-C 变异体、5-E 钻地爪臂）只放在两头堵死的路上；
  天花板上的 5-F 吊在玩家必经的路上方；原地炮台 5-D 守在路口。每一屏至少 4 个（`MIN_ENEMIES`）。
- **中段小 Boss「变异枪手」**（2026-11 用户定的）：第 6 段一间封住的房间，进去门就关、打死它前面的门才开，
  **它死了不算通关**。房间两边的墙一直通到画面顶，从房顶上绕不过去。
- **新机关**：地刺（`^`，2 格宽，写在地板上面那一格）、毒气罐（`K`，一只 48 高 = 3 行：
  单个跳得过去，**摞两只或者放进矮走廊就堵死**，打碎了才过得去）。
- **画面要满**：摄像头、蛛网吊在天花板下，监视器挂墙上，桌椅、发电机、扫描仪、阀门、管子摆在地上。

实验室的「室内」：头顶有楼板的地方铺灰蓝墙板（`map_build.THEMES["lab"]`）。
字母表：a 5-A（科学家，扔酸液瓶，挨打 / 被贴近就变身）、b 5-B（科学家，一看见人就变身）、c 5-C（变异体，砸地震波）、
d 5-D（原地炮台，三连发、能斜射）、e 5-E（埋在地下的爪臂，走近才钻出来）、f 5-F（倒挂在天花板上，滴毒液）、
m 小 Boss「变异枪手」、B 关底 Boss「生化舱」。
行号：上层地板第 7 行、中层第 13 行、地面第 20 行；敌人写在**脚下那一行的上一行**，
5-F 写在**天花板下面那一行**（`FLOAT_AT`：原点在那一格顶边往下 20，吊架顶边正好贴着天花板）。
"""

from map_canvas import Canvas, stitch

LETTERS = {"a": "5_a", "b": "5_b", "c": "5_c", "d": "5_d", "e": "5_e", "f": "5_f", "m": "5_mid", "boss": "5_boss"}
FLOATING = {"5_f", "5_boss"}
HANGING = set()
## 5-F 的吊架顶边在原点上面 20（`EnemyCeilingEmitter.MOUNT`）：写在天花板下面那一行，原点就在那一格顶边往下 20
FLOAT_AT = {"5_f": 20.0}
CHASERS = {"5_a", "5_b", "5_c", "5_e"}
MIN_ENEMIES = 4


def capsules(cv, c, row, count=1):
	"""毒气罐：第 c~c+1 列，站在第 row 行的地板上，摞 count 只（一只 48 高 = 3 行）。"""
	cv.fill(c, c + 1, row - 3 * count, row - 1, "K")


def spikes(cv, c, row, pairs=1):
	"""地刺：从第 c 列起 pairs 组（一组 2 格宽），站在第 row 行的地板上。"""
	cv.fill(c, c + 2 * pairs - 1, row - 1, row - 1, "^")


def ceiling_props(cv, row, items):
	"""吊在第 row 行天花板底下的东西（摄像头、蛛网）：贴图顶边贴着天花板。"""
	for name, c in items:
		cv.prop(name, c, row + 2)


def entrance():
	"""[绕] 第 1 段「入口」。第一屏不放敌人：门口的发电机、几块台子。
	第二屏是实验楼：从正门进一楼，**一楼走到头是墙**（墙后堆着毒气罐的仓库），顺梯子上二楼，
	二楼天花板上吊着一台发射器，从二楼的窗口出到外面的台子上、跳回地面。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.put(3, 19, "@")
	cv.prop("generator", 8, 20)
	cv.prop("table", 24, 20)
	cv.prop("chair", 27, 20)
	cv.floor(14, 19, 15, "=")
	cv.floor(24, 29, 12, "=")
	# 实验楼：屋顶第 7 行，正门在左墙下面，右墙二楼那一截是窗
	cv.floor(44, 75, 7)
	cv.fill(44, 45, 8, 15, "%")
	cv.floor(46, 73, 13)
	cv.fill(74, 75, 8, 9, "%")
	cv.fill(74, 75, 14, 19, "%")
	cv.floor(76, 79, 13, "=")
	cv.ladder(66, 13, 20)
	capsules(cv, 70, 20, 2)
	cv.put(52, 19, "a")
	cv.put(58, 19, "d")
	cv.put(62, 19, "a")
	cv.put(50, 12, "a")
	cv.put(56, 8, "f")
	cv.put(64, 12, "b")
	cv.put(70, 12, "a")
	cv.barrel(62, 13)
	cv.prop("monitor", 48, 11)
	cv.prop("scanner", 52, 20)
	ceiling_props(cv, 7, [("camera", 60), ("web", 48)])
	return cv


def gas_hall():
	"""[选] 第 2 段「毒气走廊」。**上面**：一条长廊，天花板上一排发射器往下滴毒液、科学家在廊里扔酸液瓶；
	**下面**：地面上一组组地刺、埋着的爪臂、原地炮台。左头顺梯子上长廊，两条路在右头会合。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(4, 75, 7)
	cv.floor(4, 75, 13)
	cv.ladder(2, 13, 20)
	for c in (16, 32, 48, 64):
		cv.put(c, 8, "f")
	cv.put(24, 12, "a")
	cv.put(40, 12, "b")
	cv.put(56, 12, "a")
	cv.put(70, 12, "a")
	spikes(cv, 12, 20, 2)
	spikes(cv, 36, 20, 2)
	spikes(cv, 58, 20, 2)
	cv.put(22, 19, "e")
	cv.put(30, 19, "d")
	cv.put(48, 19, "c")
	cv.put(68, 19, "e")
	cv.barrel(28, 20)
	cv.prop("tube", 8, 13)
	cv.prop("monitor2", 34, 11)
	cv.prop("valve", 44, 20)
	ceiling_props(cv, 7, [("camera", 20), ("web2", 40), ("camera", 60)])
	ceiling_props(cv, 13, [("web", 26), ("web2", 52)])
	return cv


def tanks():
	"""[绕] 第 3 段「培养舱」。地面走到一半被墙挡死，顺梯子上二楼；二楼走到头又是墙，
	**从地板的洞掉进底下的储藏室**：两只毒气罐摞起来把储藏室整个堵住，打碎了才从后门出去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(10, 70, 13)                 # 二楼地板（也是储藏室的顶）
	cv.fill(38, 39, 14, 19, "%")         # 地面走到这儿是墙
	cv.floor(40, 57, 7)                  # 二楼后半间的天花板
	cv.fill(56, 57, 8, 12, "%")          # 二楼走到头
	cv.clear(48, 49, 13, 13)             # 地板上的洞
	cv.fill(70, 71, 14, 15, "%")         # 储藏室后门上面那截墙（门 4 格高）
	cv.ladder(8, 13, 20)
	capsules(cv, 62, 20, 2)
	cv.put(16, 19, "a")
	cv.put(24, 19, "d")
	cv.put(32, 19, "e")
	cv.put(18, 12, "a")
	cv.put(30, 12, "a")
	cv.put(44, 8, "f")
	cv.put(52, 12, "b")
	cv.put(44, 19, "c")
	cv.put(56, 19, "a")
	cv.put(66, 12, "d")
	cv.put(76, 19, "a")
	cv.barrel(34, 13)
	cv.prop("tube_valve", 14, 20)
	cv.prop("monitor3", 28, 18)
	cv.prop("generator", 42, 13)
	ceiling_props(cv, 7, [("camera", 50)])
	ceiling_props(cv, 13, [("web", 20), ("web2", 46)])
	return cv


def vent_shaft():
	"""[绕] 第 4 段「沉降池」。地面断开一大截（32 格，跳不过去），**只能爬上去踩一串悬着的台子**，
	头顶的管廊下吊着一排发射器往台子上滴毒液；过去以后跳回地面。"""
	cv = Canvas(80)
	cv.ground(0, 23)
	cv.ground(56, 79)
	cv.fill(22, 23, 18, 19)              # 坑沿：冲的敌人冲不过来（地面跨段连着，左边冲过来的也会掉）
	cv.fill(56, 57, 18, 19)
	cv.floor(18, 60, 3)                  # 管廊（发射器吊在它下面）
	cv.ladder(18, 11, 20)
	cv.floor(20, 26, 11, "=")
	cv.floor(31, 36, 10, "=")
	cv.floor(41, 46, 11, "=")
	cv.floor(51, 56, 10, "=")
	cv.put(6, 19, "a")
	cv.put(12, 19, "d")
	cv.put(22, 10, "d")
	cv.put(28, 4, "f")
	cv.put(34, 9, "d")
	cv.put(38, 4, "f")
	cv.put(44, 10, "d")
	cv.put(48, 4, "f")
	cv.put(54, 9, "d")
	cv.put(64, 19, "e")
	cv.put(70, 19, "c")
	cv.put(76, 19, "d")
	cv.barrel(10, 20)
	cv.prop("valve", 2, 20)
	cv.prop("generator", 60, 20)
	ceiling_props(cv, 3, [("web", 33), ("web2", 43)])
	return cv


def turrets():
	"""[选] 第 5 段「炮台区」。**上面**一条长长的钢架走道（单向，子弹上下穿得过），科学家站在上面往下扔酸液瓶；
	**下面**地面上一台台原地炮台斜着往上打、地刺夹在中间。左头梯子上走道，或者直接走地面。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.floor(4, 74, 11, ":")
	cv.ladder(2, 11, 20)
	cv.put(14, 10, "a")
	cv.put(8, 19, "a")
	cv.put(30, 10, "b")
	cv.put(46, 10, "a")
	cv.put(62, 10, "a")
	cv.put(20, 19, "d")
	cv.put(40, 19, "d")
	cv.put(60, 19, "d")
	spikes(cv, 28, 20, 2)
	spikes(cv, 50, 20, 2)
	cv.put(70, 19, "e")
	capsules(cv, 34, 20, 1)
	cv.barrel(42, 20)
	cv.barrel(28, 11)
	cv.prop("scanner", 8, 20)
	cv.prop("table2", 44, 20)
	cv.prop("monitor", 66, 20)
	return cv


def arena():
	"""[绕] 第 6 段「小 Boss 房」。前面一截走廊（科学家、爪臂、炮台），然后是一间封住的房间：
	**两边的墙一直通到画面顶**（从房顶上绕不过去），门在墙脚。进去以后入口门关上，
	变异枪手在里面——打死它，出口门才开。房间里两块低台子（蹦起来打的那一道激光，站在地上躲；趴下躲低的那道）。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(18, 19, 0, 15, "%")          # 入口那面墙（下面 4 格是门）
	cv.put(18, 16, "[")
	cv.floor(20, 61, 13)                 # 房间的天花板
	cv.fill(62, 63, 0, 15, "%")          # 出口那面墙
	cv.put(62, 16, "]")
	cv.floor(26, 31, 16, "=")
	cv.floor(50, 55, 16, "=")
	cv.put(42, 19, "m")
	cv.put(4, 19, "a")
	cv.put(10, 19, "d")
	cv.put(14, 19, "a")
	cv.put(70, 19, "a")
	cv.put(76, 19, "d")
	# 房间里不摆 door / door2：和房间的门是同一套门柱，玩家分不清哪个是真门
	cv.prop("tube", 34, 20)
	cv.prop("tube_valve", 46, 20)
	cv.prop("monitor2", 24, 18)
	ceiling_props(cv, 13, [("camera", 30), ("camera", 52), ("web", 40)])
	cv.prop("generator", 66, 20)
	return cv


def spike_field():
	"""[绕] 第 7 段「地刺阵」。地面到这儿全是地刺，再往前是一道跳不过去的坑：
	顺梯子上二楼的长台子，台子之间的缺口跳过去，天花板上的发射器往下滴；过了坑跳回地面。"""
	cv = Canvas(80)
	cv.ground(0, 29)
	cv.ground(52, 79)
	cv.fill(28, 29, 18, 19)              # 坑沿（两边都垒）
	cv.fill(52, 53, 18, 19)
	spikes(cv, 14, 20, 6)
	cv.floor(10, 66, 5)                  # 天花板
	cv.floor(10, 24, 12)
	cv.floor(30, 40, 11)
	cv.floor(46, 60, 12)
	cv.ladder(8, 12, 20)
	cv.put(16, 6, "f")
	cv.put(34, 6, "f")
	cv.put(54, 6, "f")
	cv.put(20, 11, "d")
	cv.put(36, 10, "d")
	cv.put(56, 11, "d")
	cv.put(4, 19, "d")
	cv.put(60, 19, "e")
	cv.put(66, 19, "c")
	cv.put(74, 19, "a")
	cv.barrel(22, 12)
	cv.prop("tube", 12, 12)
	cv.prop("monitor3", 48, 10)
	ceiling_props(cv, 5, [("camera", 26), ("web", 44)])
	return cv


def crossfire():
	"""[绕] 第 8 段「三层交叉火力」。一楼前半间到头是墙，梯子上二楼；二楼有一截是单向的钢架楼板，
	楼下的炮台往上斜着打得到你、你也打得到它；二楼走到一半被墙挡住，梯子上屋顶，
	从屋顶的洞掉回二楼后半截，再从二楼的洞掉进一楼后半间出去。"""
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
	cv.put(14, 19, "d")
	cv.put(12, 12, "a")
	cv.put(30, 12, "b")
	cv.put(38, 8, "f")
	cv.put(56, 6, "a")
	cv.put(66, 6, "d")
	cv.put(60, 12, "a")
	cv.put(70, 8, "f")
	cv.put(40, 19, "e")
	cv.put(56, 19, "c")
	cv.barrel(58, 20)
	capsules(cv, 66, 20, 1)
	cv.put(72, 19, "a")
	cv.prop("generator", 28, 20)
	cv.prop("monitor", 34, 11)
	ceiling_props(cv, 7, [("camera", 30), ("web", 58)])
	return cv


def corridor():
	"""[绕] 第 9 段「隔离通道」。一条矮矮的通道（3 格高，一只毒气罐就把它堵满了），一条道走到底：
	**两只毒气罐把路堵死**（打碎才过得去），埋着的爪臂、变异体迎面过来，地刺夹在中间。
	通道太矮，发射器吊不进来（人会撞上它）。通道上面的楼上不去。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	cv.fill(4, 75, 15, 16)               # 通道的顶：底下第 17~19 行，3 格高
	cv.fill(4, 7, 0, 14, "%")
	capsules(cv, 26, 20, 1)
	capsules(cv, 52, 20, 1)
	cv.put(12, 19, "e")
	cv.put(16, 19, "d")
	cv.put(20, 19, "a")
	cv.put(34, 19, "c")
	cv.put(40, 19, "a")
	cv.put(46, 19, "e")
	cv.put(60, 19, "a")
	cv.put(66, 19, "b")
	cv.put(72, 19, "c")
	spikes(cv, 38, 20, 1)
	cv.barrel(32, 20)
	cv.barrel(58, 20)
	for c, name in ((12, "monitor2"), (40, "monitor"), (64, "monitor2")):
		cv.prop(name, c, 13)
	cv.prop("valve", 22, 15)
	cv.prop("generator", 44, 15)
	return cv


def boss_room():
	"""[选] 第 10 段「Boss 区」。生化舱飘在空中，横扫激光会一路压到地面上站着的人胸口：
	**一整片平地、没有墙**（墙挡激光也挡它的视线），头顶几块单向台子（扫的时候站在台子上的得跳下来）。"""
	cv = Canvas(80)
	cv.ground(0, 79)
	for c0, c1 in ((8, 14), (28, 34), (50, 56), (68, 74)):
		cv.floor(c0, c1, 15, "=")
	for c0, c1 in ((18, 24), (38, 44), (58, 64)):
		cv.floor(c0, c1, 11, "=")
	cv.put(2, 19, "a")
	cv.put(20, 10, "a")
	cv.put(54, 10, "B")
	cv.prop("generator", 2, 20)
	cv.prop("scanner", 40, 20)
	cv.prop("valve", 64, 20)
	return cv


SEGMENTS = [entrance, gas_hall, tanks, vent_shaft, turrets, arena, spike_field, crossfire, corridor, boss_room]


def assemble():
	return stitch([make() for make in SEGMENTS])
