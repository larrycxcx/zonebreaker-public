"""按颜色画的像素图 ↔ 格子地图（2026-10，分层关卡的第 D 步：给用户自己画关卡用）。

**一个像素就是一格**（游戏里 16×16），图**正好 23 像素高**（一屏），宽度随意但要是**偶数**（一屏 40）。
每种颜色是一种东西，颜色表就是下面的 `PALETTE`（`art_src/maps/README.md` 里有一张给人看的表）。
用任何能画像素的工具（Aseprite、Photoshop 铅笔、Windows 画图都行）画，存成 PNG。

    python tools/map_paint.py template [宽] [文件]   # 一张空白地图：地面、出生点、出口都画好了（默认 80 宽）
    python tools/map_paint.py palette                # 颜色条 art_src/maps/palette.png，画的时候用吸管取色
    python tools/map_paint.py check 图.png --level 2  # 读图 → 打印成字符画 → 跑和正式关卡一样的找路自检
    python tools/map_paint.py preview 图.png --level 2  # 生成 scenes/map_preview.tscn 并截图（每屏一张）
    python tools/map_paint.py export 2 yard 图.png    # 把现成关卡的某一段导出成图，改完再读回来
    python tools/map_paint.py selftest               # 把三关每一段导出再读回来，必须一字不差

`--level N` 决定**用哪一关的敌人和砖**：敌人颜色 a~g 在每关代表不同的敌人（见那一关的 `levelN_map.LETTERS`），
预览截图用那一关的素材包。

画好的图要放进正式关卡：在 `levelN_map.py` 里写一段

    def my_part():
        return from_png("art_src/maps/my_part.png")      # levelN_map.py 已经 import 了它

再加进 `SEGMENTS`。图里只有格子（地形、梯子、机关、敌人），**装饰自动撒**；
点名摆的大件、墙上的管道、编号牌、栏杆要在那个函数里另外加（`cv.prop(...)` 等，同 `Canvas`）。
"""
import os
import subprocess
import sys

import skin_build as sb

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
MAPS = os.path.join(ROOT, "art_src", "maps")
PREVIEW_SCENE = os.path.join(ROOT, "scenes", "map_preview.tscn")
GODOT = os.environ.get("GODOT",
	r"D:\Work\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
ROWS = 23

## (字符, 颜色, 说明)。**顺序就是颜色条上的顺序**。颜色挑的是画图工具里好调、彼此差得远的。
PALETTE = [
	(".", (255, 255, 255), "空（透明也算空）"),
	("#", (0, 0, 0), "实心：地面 / 楼板 / 墙（这一区的主材质）"),
	("%", (128, 128, 128), "实心：第二种材质（警示条纹 / 石砖 / 卷帘）"),
	("X", (128, 64, 0), "实心：掩体块（钢架箱 / 石块），按 2×2 画"),
	("=", (0, 0, 255), "单向平台：从下面跳得上来、按下+跳穿得下去"),
	(":", (0, 128, 255), "单向平台：第二种画法（钢梁 / 石台 / 木楼板）"),
	("H", (255, 255, 0), "梯子：2 格宽，从上面那层地板（含）画到下面那层地板（不含）"),
	("~", (0, 255, 255), "传送带，往右带（只有工业区有画面）"),
	("-", (0, 128, 128), "传送带，往左带"),
	("P", (255, 0, 255), "液压机：画满 2×4（吊在天花板下面，底下要有地板）"),
	("G", (128, 0, 128), "闸门：画满 2×4（上面要一直封到天花板）"),
	("K", (255, 128, 0), "可打爆的箱子：2 格宽，竖着几格就摞几只"),
	("O", (255, 0, 0), "油桶：一格"),
	("!", (192, 192, 192), "背景里竖着的管子 / 石柱（纯装饰，不挡人）"),
	("@", (0, 255, 0), "出生点（脚站在下面那一格上）"),
	(">", (0, 128, 0), "出口（脚站在下面那一格上；没有 Boss 的图一定要有）"),
	("B", (255, 128, 192), "Boss"),
	("a", (255, 160, 160), "敌人 a"),
	("b", (160, 160, 255), "敌人 b"),
	("c", (160, 255, 160), "敌人 c"),
	("d", (255, 255, 160), "敌人 d"),
	("e", (160, 255, 255), "敌人 e"),
	("f", (255, 160, 255), "敌人 f"),
	("g", (255, 200, 120), "敌人 g"),
]
CHAR_OF = {rgb: ch for ch, rgb, _ in PALETTE}
RGB_OF = {ch: rgb for ch, rgb, _ in PALETTE}
## 颜色差多少还算同一种（画图工具存图时偶尔会差一两个数）。再远就报错，不瞎猜。
TOLERANCE = 24
## 液压机、闸门在格子地图里只记左上角那一格，画的时候画满一整块
BLOCKS = {"P": (2, 4), "G": (2, 4)}


def _nearest(rgb):
	best, dist = None, None
	for ch, c, _ in PALETTE:
		d = max(abs(a - b) for a, b in zip(rgb, c))
		if dist is None or d < dist:
			best, dist = ch, d
	return best if dist <= TOLERANCE else None


def png_to_rows(path):
	"""读一张图，返回 23 行字符串。有认不出的颜色、尺寸不对、机关没画满一整块，直接报错（列出是哪几个像素）。"""
	width, height, px = sb.read_png(path)
	if height != ROWS:
		raise SystemExit("%s：图要正好 %d 像素高（一屏），现在是 %d" % (path, ROWS, height))
	if width % 2:
		raise SystemExit("%s：宽度要是偶数（管道、梯子按 2 格对齐），现在是 %d" % (path, width))
	grid = [["."] * width for _ in range(ROWS)]
	bad = []
	for y in range(ROWS):
		for x in range(width):
			p = px[y][x]
			if p[3] < 128:
				continue
			ch = _nearest(p[:3])
			if ch is None:
				bad.append("(%d, %d) = #%02x%02x%02x" % (x, y, p[0], p[1], p[2]))
			else:
				grid[y][x] = ch
	if bad:
		raise SystemExit("%s：有 %d 个像素的颜色不在颜色表里（列 x、行 y）：\n  %s"
			% (path, len(bad), "\n  ".join(bad[:20]) + ("\n  ……" if len(bad) > 20 else "")))
	_collapse_blocks(grid, path)
	return ["".join(r) for r in grid]


def _collapse_blocks(grid, path):
	"""液压机 / 闸门画的是一整块 2×4，格子地图里只留左上角那一格。"""
	width = len(grid[0])
	seen = set()
	for y in range(ROWS):
		for x in range(width):
			ch = grid[y][x]
			if ch not in BLOCKS or (x, y) in seen:
				continue
			w, h = BLOCKS[ch]
			cells = [(x + dx, y + dy) for dy in range(h) for dx in range(w)]
			if any(cx >= width or cy >= ROWS or grid[cy][cx] != ch for cx, cy in cells):
				raise SystemExit("%s：(%d, %d) 那块 %s 要画满 %d×%d（左上角从这儿开始）" % (path, x, y, ch, w, h))
			for cx, cy in cells:
				seen.add((cx, cy))
				grid[cy][cx] = "."
			grid[y][x] = ch


def rows_to_png(rows, path):
	width = len(rows[0])
	px = [[(255, 255, 255, 255)] * width for _ in range(ROWS)]
	for y, line in enumerate(rows):
		for x, ch in enumerate(line):
			if ch not in RGB_OF:
				raise SystemExit("第 %d 行第 %d 列的 %r 不在颜色表里" % (y, x, ch))
			px[y][x] = RGB_OF[ch] + (255,)
	# 机关最后画、画满一整块（先画的话，后面那几格的「空」会把它盖回去）
	for y, line in enumerate(rows):
		for x, ch in enumerate(line):
			if ch in BLOCKS:
				w, h = BLOCKS[ch]
				for dy in range(h):
					for dx in range(w):
						if y + dy < ROWS and x + dx < width:
							px[y + dy][x + dx] = RGB_OF[ch] + (255,)
	os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
	sb.write_png(path, px)


def _level(key):
	"""那一关的地图模块和 `STAGES` 里那一条（敌人表、砖、素材包）。"""
	import importlib
	import level_build as lb
	if key not in lb.STAGES or not lb.STAGES[key].get("map"):
		raise SystemExit("--level 要填一个格子地图关（%s）" % "、".join(k for k, v in lb.STAGES.items() if v.get("map")))
	lb.use_stage(key)
	return importlib.import_module(lb.STAGES[key]["map"]), lb.STAGES[key]


def _map_level(rows, plan, stage):
	import level_build as lb
	import map_build as mb
	mb.use_theme(stage["theme"])
	unknown = sorted({ch for r in rows for ch in r if ch.islower() and ch not in plan.LETTERS})
	if unknown:
		raise SystemExit("敌人 %s 在这一关没有（这一关有 %s）" % ("、".join(unknown), "、".join(
			"%s=%s" % (k, v) for k, v in plan.LETTERS.items() if k != "boss")))
	return mb.MapLevel(rows, plan.LETTERS, stage["enemies"], lb.stand_of, plan.FLOATING, plan.HANGING,
		getattr(plan, "FLOAT_AT", None))


def _complete(rows, plan, stage):
	"""单独拿出来的一段（比如导出的中间段）没有出生点和出口：出生点放在最左边能站的最低那一格，
	出口放在最右边能站的最低那一格。补了就说一声，并且不查「出生那一屏不放敌人」（那是整关开头才有的规矩）。"""
	text = "".join(rows)
	if "@" in text and (">" in text or "B" in text):
		return rows, False
	grid = [list(r) for r in rows]
	level = _map_level(rows, plan, stage)
	width = len(rows[0])
	notes, added = [], []
	for ch, cols, what in (("@", range(0, width), "出生点"), (">", range(width - 1, -1, -1), "出口")):
		if ch in text or (ch == ">" and "B" in text):
			continue
		for c in cols:
			spot = next((r for r in range(ROWS - 1, 0, -1) if level.standable(r, c) and grid[r - 1][c] == "."), None)
			if spot is not None:
				grid[spot - 1][c] = ch
				notes.append("%s放在第 %d 列、站在第 %d 行" % (what, c, spot))
				added.append(what)
				break
	print("（图里没画%s，自己补上了：%s）" % ("和".join(added), "；".join(notes)))
	return ["".join(r) for r in grid], True


def check(path, key, safe):
	import map_build as mb
	import map_canvas
	plan, stage = _level(key)
	rows = png_to_rows(path)
	rows, added = _complete(rows, plan, stage)
	safe = safe and not added
	map_canvas.dump(rows)
	level = _map_level(rows, plan, stage)
	problems = mb.check(level, safe_cols=mb.SAFE_COLS if safe else 0, chasers=plan.CHASERS)
	print()
	print("%d 格宽（%d 屏）、梯子 %d、液压机 %d、闸门 %d、箱子 %d、油桶 %d、敌人 %d"
		% (level.width, level.width // 40, len(level.ladders), len(level.presses), len(level.gates),
			len(level.crates), len(level.barrels), len(level.enemies)))
	if problems:
		print("自检没过：")
		for p in problems:
			print("  -", p)
		return False
	print("自检通过：从出生点走得到%s。" % ("Boss" if level.boss_cell else "出口"))
	return True


def preview(path, key, safe):
	"""生成 scenes/map_preview.tscn，再用 Godot 按这一关的素材包截图（每屏一张）。"""
	import map_build as mb
	if not check(path, key, safe):
		raise SystemExit(1)
	plan, stage = _level(key)
	rows, _ = _complete(png_to_rows(path), plan, stage)
	level = _map_level(rows, plan, stage)
	mb.build(level, PREVIEW_SCENE, "MapPreview", stage["prop_dir"], True, stage["prop_frames"])
	name = os.path.splitext(os.path.basename(path))[0]
	out = os.path.join(MAPS, "preview")
	os.makedirs(out, exist_ok=True)
	print("截图（Godot 要开窗口渲染，会闪一下）……")
	subprocess.run([GODOT, "--path", ROOT, "--import", "--headless"], capture_output=True)
	subprocess.run([GODOT, "--path", ROOT, "--script", "res://tools/map_shot.gd", "--",
		"res://scenes/map_preview.tscn", "res://levels/level_%s.tres" % key, out, name],
		capture_output=True)
	shots = sorted(f for f in os.listdir(out) if f.startswith(name + "_"))
	for f in shots:
		print("  ", os.path.join(out, f))
	if not shots:
		raise SystemExit("没截到图：看看 Godot 的路径对不对（环境变量 GODOT 可以改）")


def export(key, segment, path):
	plan, _ = _level(key)
	make = getattr(plan, segment, None)
	if make is None or make not in plan.SEGMENTS:
		raise SystemExit("第 %s 关没有叫 %s 的段（有 %s）" % (key, segment, "、".join(f.__name__ for f in plan.SEGMENTS)))
	rows_to_png(make().rows(), path)
	print("写入", path)


def template(width, path):
	if width % 2:
		raise SystemExit("宽度要是偶数")
	grid = [["."] * width for _ in range(ROWS)]
	for y in range(20, ROWS):
		grid[y] = ["#"] * width
	grid[19][3] = "@"
	grid[19][width - 3] = ">"
	rows_to_png(["".join(r) for r in grid], path)
	print("写入", path)


def palette(path):
	size = 8
	px = [[(255, 255, 255, 255)] * (len(PALETTE) * size) for _ in range(size)]
	for i, (_, rgb, _) in enumerate(PALETTE):
		for y in range(size):
			for x in range(size):
				# 白色那格画一圈灰边，不然看不出来
				edge = (x in (0, size - 1) or y in (0, size - 1)) and rgb == (255, 255, 255)
				px[y][i * size + x] = (200, 200, 200, 255) if edge else rgb + (255,)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	sb.write_png(path, px)
	print("写入", path)


def selftest():
	"""三关每一段：导出成图、再读回来，格子必须一字不差（机关只留左上角那条规矩也在里面）。"""
	import tempfile
	ok = True
	for key in ("1", "2", "3"):
		plan, _ = _level(key)
		for make in plan.SEGMENTS:
			rows = make().rows()
			tmp = os.path.join(tempfile.gettempdir(), "map_paint_selftest.png")
			rows_to_png(rows, tmp)
			back = png_to_rows(tmp)
			same = back == rows
			ok = ok and same
			print("第 %s 关 %-12s %s" % (key, make.__name__, "一致" if same else "不一致！"))
	if not ok:
		raise SystemExit(1)


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	opts = sys.argv[1:]
	key = opts[opts.index("--level") + 1] if "--level" in opts else None
	if key in args:
		args.remove(key)
	safe = "--no-safe" not in opts
	if not args:
		print(__doc__)
		return
	cmd = args[0]
	if cmd == "template":
		width = int(args[1]) if len(args) > 1 else 80
		template(width, args[2] if len(args) > 2 else os.path.join(MAPS, "template.png"))
	elif cmd == "palette":
		palette(os.path.join(MAPS, "palette.png"))
	elif cmd in ("check", "preview"):
		if len(args) < 2 or key is None:
			raise SystemExit("用法：python tools/map_paint.py %s 图.png --level N" % cmd)
		if cmd == "check":
			raise SystemExit(0 if check(args[1], key, safe) else 1)
		preview(args[1], key, safe)
	elif cmd == "export":
		if len(args) < 4:
			raise SystemExit("用法：python tools/map_paint.py export 关 段名 图.png")
		export(args[1], args[2], args[3])
	elif cmd == "selftest":
		selftest()
	else:
		raise SystemExit("不认识的命令 %s（%s）" % (cmd, "template / palette / check / preview / export / selftest"))


if __name__ == "__main__":
	main()
