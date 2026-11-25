"""Generates the cyberpunk skin pack's HUD art from the GUI art pack and gun art, output to skins/cyberpunk/hud/.

    python tools/hud_build.py            # regenerate everything
    python tools/hud_build.py --check    # only check, without writing files

Art sources: CraftPix's GUI pack (art_in/default/gui/, not in the repo) and the guns in the character pack (art_in/default/2 Guns/).

- Health bar: `2 Bars/HealthBar1~8`, 32×14 each. 1~4 are full (red): left end, middle, right end, single cell; 5~8 are empty slots of the same shapes (grey).
  One cell per point of player health; the boss bar strings the same set into a long bar, cropped by ratio. Output `health.png`: a row of 8 pieces in the art's order.
- Stamina bar: `2 Bars/EnergyBar1~8`, 16×5 each, the same pattern (1~4 blue, 5~8 empty). Plus a recoloured orange set for "too tired to run"
  (the old placeholder bar also turned orange when stamina fell below the threshold for sprinting again). Output `energy.png`: 4 full + 4 empty + 4 orange.
- Frame: the 32×32 box in row 8 of `1 Frames/FrameMap.png`, used for both the weapon slot and the boss portrait frame (stretched with NinePatchRect in the scene).
- Weapon icons: the original images of the two guns in the player's hands — rifle number 4, grenade launcher number 5, the same pair as `GUNS` in skin_build.py.
- Ultimate icon: the red aerial bomb number 18 from the explosion pack (art_in/default/explosions/1 Bombs/), with the blank border cropped (10×21).
  The blue one (number 20) is 23×40, too tall for that row on the HUD.
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
GUI = os.path.join(HERE, "..", "art_in", "default", "gui")
GUNS_DIR = os.path.join(HERE, "..", "art_in", "default", "2 Guns")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "hud")

FRAME_AT = (224, 256)  # The top-left corner of that box in FrameMap
# Stamina bar recolour: blue → orange (too tired to run)
TIRED = {(51, 104, 220): (210, 47, 30), (61, 171, 234): (255, 129, 66), (91, 236, 241): (255, 218, 69)}
GUNS = {"rifle": 4, "launcher": 5}
BOMB = os.path.join(HERE, "..", "art_in", "default", "explosions", "1 Bombs", "18.png")


def trim(p):
	"""Crop away fully transparent rows and columns around the edges."""
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
		sys.exit("Cannot find the GUI art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(GUI))
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
