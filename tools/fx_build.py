"""Generates the cyberpunk skin pack's effect art from the explosion pack and muzzle effect art, output to skins/cyberpunk/fx/.

    python tools/fx_build.py            # regenerate everything
    python tools/fx_build.py --check    # only check, without writing files

Art sources (CraftPix, none in the repo):
- The explosion pack `art_in/default/explosions/3 Effects/`: four sizes (Tiny 32, Low 48, Middle 72, High 96, square frames),
  three kinds each (1 green, 2 red + dark blue, 3 lightning).
  - **Grenade explosions** use number 2, all four sizes output (`explosion_<side>.png`), and `SpriteExplosion` picks the size closest to the radius and draws it 1:1.
  - **Sparks when a character is hit** use Tiny number 2 (`hit.png`, 32×32 × 8 frames): a small red burst that clearly says "hit".
- The character pack's `art_in/default/4 Shoot_effects/`: white silhouettes, each with a level (`_1`) and a diagonal 45° (`_2`) sheet, 6 frames of 48×48 each,
  spraying right / down-right from the left edge of the cell (the muzzle). The colour is tinted in the scene with `tint`.
  - **Muzzle flashes** use number 9 (a burst with sparks).
  - **Bullets hitting a wall** use number 6 (fine scattered sparks), splashing back the way the bullet came.
  Pixel art cannot be rotated 45° at runtime, so like the bullets they are pre-made in 8 directions (`<name>/<direction>.png`). Each is first moved into a 96×96 cell
  so **the spray point (muzzle) is exactly at the cell centre** — at (0, 24) of the original cell for the level one, (0, 0) for the diagonal — and the other directions are flipped / rotated around the centre,
  so the effect's origin is the muzzle and it never sits off wherever it is placed.
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
BLASTS = os.path.join(HERE, "..", "art_in", "default", "explosions", "3 Effects")
SHOTS = os.path.join(HERE, "..", "art_in", "default", "4 Shoot_effects")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "fx")
SIZES = {32: "1 Tiny", 48: "2 Low", 72: "3 Middle", 96: "4 High"}
KIND = "2"  # The red + dark blue kind

SHOT_CELL = 48
CELL = 96
CENTER = CELL // 2
# Where the spray point is in the original cell: the level sheet, the diagonal sheet
LEVEL_ORIGIN = (0, 24)
DIAGONAL_ORIGIN = (0, 0)
# Name → which muzzle effect number
DIRECTIONAL = {"muzzle": 9, "impact": 6}
# Direction name → (use the level or the diagonal sheet, how to transform (dx, dy) relative to the spray point into this direction)
DIRECTIONS = {
	"right": ("level", lambda dx, dy: (dx, dy)),
	"left": ("level", lambda dx, dy: (-dx, dy)),
	"down": ("level", lambda dx, dy: (-dy, dx)),
	"up": ("level", lambda dx, dy: (dy, -dx)),
	"down_right": ("diagonal", lambda dx, dy: (dx, dy)),
	"down_left": ("diagonal", lambda dx, dy: (-dx, dy)),
	"up_right": ("diagonal", lambda dx, dy: (dx, -dy)),
	"up_left": ("diagonal", lambda dx, dy: (-dx, -dy)),
}


def directional(number, write):
	sources = {
		"level": (sb.read_png(os.path.join(SHOTS, "%d_1.png" % number))[2], LEVEL_ORIGIN),
		"diagonal": (sb.read_png(os.path.join(SHOTS, "%d_2.png" % number))[2], DIAGONAL_ORIGIN),
	}
	frames = len(sources["level"][0][0]) // SHOT_CELL
	for name, (which, turn) in DIRECTIONS.items():
		pixels, (ox, oy) = sources[which]
		strip = sb.blank(CELL * frames, CELL)
		for f in range(frames):
			for y in range(SHOT_CELL):
				for x in range(SHOT_CELL):
					c = pixels[y][f * SHOT_CELL + x]
					if c[3] <= 8:
						continue
					tx, ty = turn(x - ox, y - oy)
					strip[CENTER + ty][f * CELL + CENTER + tx] = c
		yield name, strip, frames


def main():
	write = "--check" not in sys.argv
	for folder in (BLASTS, SHOTS):
		if not os.path.isdir(folder):
			sys.exit("Cannot find the effect art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(folder))
	print("Explosions:")
	for size, folder in SIZES.items():
		width, height, pixels = sb.read_png(os.path.join(BLASTS, folder, KIND + ".png"))
		assert height == size and width % size == 0, "%s/%s.png is not a row of %d×%d frames" % (folder, KIND, size, size)
		if write:
			sb.write_png(os.path.join(OUT, "explosion_%d.png" % size), pixels)
		print("  fx/explosion_%d.png  %d frames" % (size, width // size))
	print("Sparks when a character is hit:")
	width, _, pixels = sb.read_png(os.path.join(BLASTS, "1 Tiny", KIND + ".png"))
	if write:
		sb.write_png(os.path.join(OUT, "hit.png"), pixels)
	print("  fx/hit.png  %d frames" % (width // 32))
	for name, number in DIRECTIONAL.items():
		print("%s (muzzle effect no. %d):" % (name, number))
		for direction, strip, frames in directional(number, write):
			if write:
				sb.write_png(os.path.join(OUT, name, direction + ".png"), strip)
			print("  fx/%s/%s.png  %d frames" % (name, direction, frames))


if __name__ == "__main__":
	main()
