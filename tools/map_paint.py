"""Pixel images painted by colour ↔ grid maps (2026-10, step D of layered stages: for the user to draw stages themselves).

**One pixel is one cell** (16×16 in the game), the image is **exactly 23 pixels tall** (one screen), and any width but it has to be **even** (a screen is 40).
Each colour is one kind of thing, and the palette is `PALETTE` below (`art_src/maps/README.md` has a table for people).
Paint with any tool that can draw pixels (Aseprite, Photoshop's pencil, Windows Paint all work) and save as PNG.

    python tools/map_paint.py template [width] [file]   # a blank map: ground, spawn and exit already drawn (80 wide by default)
    python tools/map_paint.py palette                # the colour strip art_src/maps/palette.png, for the eyedropper while painting
    python tools/map_paint.py check img.png --level 2  # read the image → print it as characters → run the same pathfinding self-check as the real stages
    python tools/map_paint.py preview img.png --level 2  # generate scenes/map_preview.tscn and take screenshots (one per screen)
    python tools/map_paint.py export 2 yard img.png    # export a segment of an existing stage as an image, to edit and read back
    python tools/map_paint.py selftest               # export every segment of the three stages and read them back; they must match exactly

`--level N` decides **which stage's enemies and tiles to use**: the enemy colours a~g mean different enemies in each stage (see that stage's `levelN_map.LETTERS`),
and preview screenshots use that stage's art pack.

To put a painted image into a real stage: write a segment in `levelN_map.py`

    def my_part():
        return from_png("art_src/maps/my_part.png")      # levelN_map.py already imports it

and add it to `SEGMENTS`. The image only has cells (terrain, ladders, traps, enemies), and **props are scattered automatically**;
big pieces placed by name, wall pipes, number signs and railings are added separately in that function (`cv.prop(...)` and so on, as with `Canvas`).
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

## (character, colour, description). **The order is the order on the colour strip**. The colours were picked to be easy to set in paint tools and far apart from each other.
PALETTE = [
	(".", (255, 255, 255), "empty (transparent counts as empty)"),
	("#", (0, 0, 0), "solid: ground / floor / wall (this zone's main material)"),
	("%", (128, 128, 128), "solid: the second material (warning stripes / stone brick / shutters)"),
	("X", (128, 64, 0), "solid: cover block (steel crate / stone), drawn as 2×2"),
	("=", (0, 0, 255), "one-way platform: can be jumped onto from below, down+jump drops through"),
	(":", (0, 128, 255), "one-way platform: the second look (girder / stone ledge / wooden floor)"),
	("H", (255, 255, 0), "ladder: 2 cells wide, drawn from the floor above (included) to the floor below (not included)"),
	("~", (0, 255, 255), "conveyor running right (only the industrial zone has the art)"),
	("-", (0, 128, 128), "conveyor running left"),
	("P", (255, 0, 255), "hydraulic press: fill 2×4 (hangs under a ceiling, needs a floor below)"),
	("G", (128, 0, 128), "blast gate: fill 2×4 (has to be sealed all the way up to the ceiling)"),
	("K", (255, 128, 0), "breakable crate: 2 cells wide, as many stacked as cells tall"),
	("O", (255, 0, 0), "barrel: one cell"),
	("!", (192, 192, 192), "a vertical pipe / stone pillar in the background (decoration only, does not block people)"),
	("@", (0, 255, 0), "spawn (feet on the cell below)"),
	(">", (0, 128, 0), "exit (feet on the cell below; required in images without a boss)"),
	("B", (255, 128, 192), "Boss"),
	("a", (255, 160, 160), "enemy a"),
	("b", (160, 160, 255), "enemy b"),
	("c", (160, 255, 160), "enemy c"),
	("d", (255, 255, 160), "enemy d"),
	("e", (160, 255, 255), "enemy e"),
	("f", (255, 160, 255), "enemy f"),
	("g", (255, 200, 120), "enemy g"),
]
CHAR_OF = {rgb: ch for ch, rgb, _ in PALETTE}
RGB_OF = {ch: rgb for ch, rgb, _ in PALETTE}
## How far apart colours can be and still count as the same (paint tools occasionally save a value or two off). Any further is an error, no guessing.
TOLERANCE = 24
## Presses and gates only record the top-left cell in a grid map, but are painted as a whole block
BLOCKS = {"P": (2, 4), "G": (2, 4)}


def _nearest(rgb):
	best, dist = None, None
	for ch, c, _ in PALETTE:
		d = max(abs(a - b) for a, b in zip(rgb, c))
		if dist is None or d < dist:
			best, dist = ch, d
	return best if dist <= TOLERANCE else None


def png_to_rows(path):
	"""Read an image and return 23 row strings. Unknown colours, the wrong size, or a trap not filling its whole block are errors (listing which pixels)."""
	width, height, px = sb.read_png(path)
	if height != ROWS:
		raise SystemExit("%s: the image has to be exactly %d pixels tall (one screen), it is %d" % (path, ROWS, height))
	if width % 2:
		raise SystemExit("%s: the width has to be even (pipes and ladders align to 2 cells), it is %d" % (path, width))
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
		raise SystemExit("%s: %d pixels have colours not in the palette (column x, row y):\n  %s"
			% (path, len(bad), "\n  ".join(bad[:20]) + ("\n  ……" if len(bad) > 20 else "")))
	_collapse_blocks(grid, path)
	return ["".join(r) for r in grid]


def _collapse_blocks(grid, path):
	"""A press / gate is painted as a whole 2×4 block; the grid map only keeps the top-left cell."""
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
				raise SystemExit("%s: the block at (%d, %d), %s, has to fill %d×%d (with its top-left corner here)" % (path, x, y, ch, w, h))
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
				raise SystemExit("Row %d, column %d: %r is not in the palette" % (y, x, ch))
			px[y][x] = RGB_OF[ch] + (255,)
	# Traps are drawn last and fill a whole block (drawn first, the "empty" of the later cells would paint over them)
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
	"""That stage's map module and its entry in `STAGES` (enemy table, tiles, art pack)."""
	import importlib
	import level_build as lb
	if key not in lb.STAGES or not lb.STAGES[key].get("map"):
		raise SystemExit("--level must be a grid map stage (%s)" % ", ".join(k for k, v in lb.STAGES.items() if v.get("map")))
	lb.use_stage(key)
	return importlib.import_module(lb.STAGES[key]["map"]), lb.STAGES[key]


def _map_level(rows, plan, stage):
	import level_build as lb
	import map_build as mb
	mb.use_theme(stage["theme"])
	unknown = sorted({ch for r in rows for ch in r if ch.islower() and ch not in plan.LETTERS})
	if unknown:
		raise SystemExit("Enemies %s are not in this stage (it has %s)" % (", ".join(unknown), ", ".join(
			"%s=%s" % (k, v) for k, v in plan.LETTERS.items() if k != "boss")))
	return mb.MapLevel(rows, plan.LETTERS, stage["enemies"], lb.stand_of, plan.FLOATING, plan.HANGING,
		getattr(plan, "FLOAT_AT", None))


def _complete(rows, plan, stage):
	"""A segment taken out on its own (such as an exported middle segment) has no spawn or exit: the spawn goes on the lowest standable cell on the far left,
	the exit on the lowest standable cell on the far right. When added it says so, and does not check "no enemies on the spawn screen" (a rule only for the start of a whole stage)."""
	text = "".join(rows)
	if "@" in text and (">" in text or "B" in text):
		return rows, False
	grid = [list(r) for r in rows]
	level = _map_level(rows, plan, stage)
	width = len(rows[0])
	notes, added = [], []
	for ch, cols, what in (("@", range(0, width), "spawn"), (">", range(width - 1, -1, -1), "exit")):
		if ch in text or (ch == ">" and "B" in text):
			continue
		for c in cols:
			spot = next((r for r in range(ROWS - 1, 0, -1) if level.standable(r, c) and grid[r - 1][c] == "."), None)
			if spot is not None:
				grid[spot - 1][c] = ch
				notes.append("%s placed in column %d, standing on row %d" % (what, c, spot))
				added.append(what)
				break
	print("(the image had no %s, added automatically: %s)" % (" and ".join(added), "; ".join(notes)))
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
	print("%d cells wide (%d screens), ladders %d, presses %d, gates %d, crates %d, barrels %d, enemies %d"
		% (level.width, level.width // 40, len(level.ladders), len(level.presses), len(level.gates),
			len(level.crates), len(level.barrels), len(level.enemies)))
	if problems:
		print("Self-check failed:")
		for p in problems:
			print("  -", p)
		return False
	print("Self-check passed: the %s can be reached from the spawn." % ("Boss" if level.boss_cell else "exit"))
	return True


def preview(path, key, safe):
	"""Generate scenes/map_preview.tscn, then take screenshots with Godot using this stage's art pack (one per screen)."""
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
	print("Taking screenshots (Godot needs to open a window to render, it will flash)……")
	subprocess.run([GODOT, "--path", ROOT, "--import", "--headless"], capture_output=True)
	subprocess.run([GODOT, "--path", ROOT, "--script", "res://tools/map_shot.gd", "--",
		"res://scenes/map_preview.tscn", "res://levels/level_%s.tres" % key, out, name],
		capture_output=True)
	shots = sorted(f for f in os.listdir(out) if f.startswith(name + "_"))
	for f in shots:
		print("  ", os.path.join(out, f))
	if not shots:
		raise SystemExit("No screenshots taken: check that the Godot path is right (the GODOT environment variable can change it)")


def export(key, segment, path):
	plan, _ = _level(key)
	make = getattr(plan, segment, None)
	if make is None or make not in plan.SEGMENTS:
		raise SystemExit("Stage %s has no segment called %s (it has %s)" % (key, segment, ", ".join(f.__name__ for f in plan.SEGMENTS)))
	rows_to_png(make().rows(), path)
	print("Wrote", path)


def template(width, path):
	if width % 2:
		raise SystemExit("The width has to be even")
	grid = [["."] * width for _ in range(ROWS)]
	for y in range(20, ROWS):
		grid[y] = ["#"] * width
	grid[19][3] = "@"
	grid[19][width - 3] = ">"
	rows_to_png(["".join(r) for r in grid], path)
	print("Wrote", path)


def palette(path):
	size = 8
	px = [[(255, 255, 255, 255)] * (len(PALETTE) * size) for _ in range(size)]
	for i, (_, rgb, _) in enumerate(PALETTE):
		for y in range(size):
			for x in range(size):
				# Draw a grey border around the white cell, or it cannot be seen
				edge = (x in (0, size - 1) or y in (0, size - 1)) and rgb == (255, 255, 255)
				px[y][i * size + x] = (200, 200, 200, 255) if edge else rgb + (255,)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	sb.write_png(path, px)
	print("Wrote", path)


def selftest():
	"""Every segment of the three stages: export as an image and read back; the cells have to match exactly (the rule that traps keep only the top-left corner is included)."""
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
			print("Stage %s %-12s %s" % (key, make.__name__, "identical" if same else "DIFFERENT!"))
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
			raise SystemExit("Usage: python tools/map_paint.py %s image.png --level N" % cmd)
		if cmd == "check":
			raise SystemExit(0 if check(args[1], key, safe) else 1)
		preview(args[1], key, safe)
	elif cmd == "export":
		if len(args) < 4:
			raise SystemExit("Usage: python tools/map_paint.py export stage segment image.png")
		export(args[1], args[2], args[3])
	elif cmd == "selftest":
		selftest()
	else:
		raise SystemExit("Unknown command %s (%s)" % (cmd, "template / palette / check / preview / export / selftest"))


if __name__ == "__main__":
	main()
