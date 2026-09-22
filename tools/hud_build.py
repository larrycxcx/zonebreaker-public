"""从 GUI 素材包和枪械素材生成赛博朋克皮肤包的 HUD 贴图，输出到 skins/cyberpunk/hud/。

    python tools/hud_build.py            # 全部重新生成
    python tools/hud_build.py --check    # 只检查，不写文件

素材来源：CraftPix 的 GUI 包（art_in/default/gui/，不进仓库）和角色包里的枪（art_in/default/2 Guns/）。

- 血条：`2 Bars/HealthBar1~8`，每块 32×14。1~4 是满的（红）：左端、中段、右端、单独一格；5~8 是同样形状的空槽（灰）。
  玩家一点血一格；Boss 血条用同一套拼一长条，按比例裁。输出 `health.png`：一排 8 块，顺序和素材一样。
- 体力条：`2 Bars/EnergyBar1~8`，每块 16×5，规律同上（1~4 蓝、5~8 空）。另外换色做一套「跑不动」的橙色
  （体力跌到能重新起跑的门槛以下时，原来的占位条也是变橙）。输出 `energy.png`：满 4 块 + 空 4 块 + 橙 4 块。
- 框：`1 Frames/FrameMap.png` 里第 8 行那个 32×32 的方框，武器槽和 Boss 头像框都用它（场景里用 NinePatchRect 拉大小）。
- 武器图标：直接用玩家手里那两把枪的原图——步枪 4 号、榴弹枪 5 号，和 skin_build.py 的 `GUNS` 同一对。
- 终极武器图标：爆炸包（art_in/default/explosions/1 Bombs/）18 号红色航弹，裁掉四周空白（10×21）。
  蓝色那颗（20 号）本体 23×40，放进 HUD 那一排太高。
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
GUI = os.path.join(HERE, "..", "art_in", "default", "gui")
GUNS_DIR = os.path.join(HERE, "..", "art_in", "default", "2 Guns")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "hud")

FRAME_AT = (224, 256)  # FrameMap 里那个方框的左上角
# 体力条换色：蓝 → 橙（跑不动）
TIRED = {(51, 104, 220): (210, 47, 30), (61, 171, 234): (255, 129, 66), (91, 236, 241): (255, 218, 69)}
GUNS = {"rifle": 4, "launcher": 5}
BOMB = os.path.join(HERE, "..", "art_in", "default", "explosions", "1 Bombs", "18.png")


def trim(p):
	"""裁掉四周全透明的行列。"""
	rows = [y for y, row in enumerate(p) if any(c[3] > 8 for c in row)]
	cols = [x for x in range(len(p[0])) if any(row[x][3] > 8 for row in p)]
	return sb.cut(p, cols[0], rows[0], cols[-1] - cols[0] + 1, rows[-1] - rows[0] + 1)


def strip(pieces):
	width = sum(len(p[0]) for p in pieces)
	out = sb.blank(width, len(pieces[0]))
	x = 0
	for p in pieces:
		sb.blit(out, p, x, 0, "strip")
		x += len(p[0])
	return out


def recolor(p, mapping):
	return [[mapping[c[:3]] + (c[3],) if c[3] > 8 and c[:3] in mapping else c for c in row] for row in p]


def load(*parts):
	return sb.read_png(os.path.join(*parts))[2]


def save(name, pixels, write):
	if write:
		sb.write_png(os.path.join(OUT, name), pixels)
	print("  hud/%s  %dx%d" % (name, len(pixels[0]), len(pixels)))


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(GUI):
		sys.exit("找不到 GUI 素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(GUI))
	health = [load(GUI, "2 Bars", "HealthBar%d.png" % i) for i in range(1, 9)]
	save("health.png", strip(health), write)
	energy = [load(GUI, "2 Bars", "EnergyBar%d.png" % i) for i in range(1, 9)]
	save("energy.png", strip(energy + [recolor(p, TIRED) for p in energy[:4]]), write)
	frames = load(GUI, "1 Frames", "FrameMap.png")
	save("frame.png", sb.cut(frames, FRAME_AT[0], FRAME_AT[1], 32, 32), write)
	for look, number in GUNS.items():
		save("gun_%s.png" % look, load(GUNS_DIR, "%d_1.png" % number), write)
	save("ultimate.png", trim(sb.read_png(BOMB)[2]), write)


if __name__ == "__main__":
	main()
