"""Picks bullet and grenade art from the art packs and generates the cyberpunk skin pack's projectile visuals, output to skins/cyberpunk/projectiles/<name>/.

    python tools/projectile_build.py            # regenerate everything
    python tools/projectile_build.py --check    # only check, without writing files

Art source: art_in/default/5 Bullets/ (CraftPix, not in the repo). Two images per bullet: `N.png` level facing right, `N_2.png` diagonal 45° (facing down-right).
In the game bullets only fly in 8 directions, so each bullet is pre-made as 8 images here (right / left / up / down / up_right / ...),
and `ProjectileAppearance` picks one by flight direction — pixel art cannot be rotated 45° at runtime, it would blur.
Grenades are round, so only one `ball.png` is output, without directions.

Which to pick (`BULLETS` / `GRENADES`):
- Player rifle: number 3, a yellow-orange tracer — following on from the yellow placeholder bullets.
- Enemies (patrollers, bosses): number 6, red and white with a black outline, instantly recognisable as enemy fire.
- Turret: number 5, a big cyan plasma ball, matching its green body.
- E (drone): number 4, a thin cyan laser, the same colour as the discharge it fires downward.
- Grenade: number 4 from the explosion pack (art_in/default/explosions/1 Bombs/), a small blue-green canister, 7×10, about the size of the 8px hitbox;
  its own 4-frame animation (`4_1.png`) tumbles in the air and loops while the grenade flies. The one F bats out is recoloured orange-red (`ENEMY_GRENADE_COLORS`),
  all colours taken from the art pack's own palette. Output `spin.png`: a row of 4 frames of 16×16.
- Boss A's missile fan: the round bullet that comes with number 3 of the boss pack (12×8), recoloured red and orange to mark it as enemy fire. Round means no direction,
  so the fan can fire at any angle (with only 8 directions of pixel art, a fan of one shot every 20° would be drawn crooked).
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "5 Bullets")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "projectiles")

BULLETS = {
	"player_bullet": "3",
	"enemy_bullet": "6",
	"turret_bullet": "5",
	"flyer_bullet": "4",
}
CYAN = (91, 236, 241)
ORANGE = (255, 129, 66)
BOSS_BALL = os.path.join(HERE, "..", "art_in", "default", "boss", "3", "Ball.png")
BOSS_BALL_COLORS = {(139, 171, 191): (255, 129, 66), (52, 30, 26): (210, 47, 30)}
GRENADE = os.path.join(HERE, "..", "art_in", "default", "explosions", "1 Bombs", "4_1.png")
ENEMY_GRENADE_COLORS = {
	(61, 171, 234): (255, 129, 66), (51, 104, 220): (210, 47, 30), (31, 31, 170): (128, 12, 83),
	(70, 198, 87): (255, 218, 69), (201, 236, 133): (255, 246, 174), (21, 137, 104): (171, 31, 101),
}
GRENADES = {
	"player_grenade": {},
	"enemy_grenade": ENEMY_GRENADE_COLORS,
}


def load(name):
	_, _, pixels = sb.read_png(os.path.join(PACK, name + ".png"))
	return pixels


def flip_h(p):
	return [row[::-1] for row in p]


def flip_v(p):
	return p[::-1]


def rotate_cw(p):
	"""Rotate 90° clockwise: a bullet facing right becomes facing down."""
	height, width = len(p), len(p[0])
	return [[p[height - 1 - x][y] for x in range(height)] for y in range(width)]


def directions(level, diagonal):
	"""The level (facing right) and diagonal (facing down-right) images → 8 directions."""
	down = rotate_cw(level)
	return {
		"right": level,
		"left": flip_h(level),
		"down": down,
		"up": flip_v(down),
		"down_right": diagonal,
		"down_left": flip_h(diagonal),
		"up_right": flip_v(diagonal),
		"up_left": flip_h(flip_v(diagonal)),
	}


def recolor(p, mapping):
	return [[mapping[c[:3]] + (c[3],) if c[3] > 8 and c[:3] in mapping else c for c in row] for row in p]


def save(folder, name, pixels, write):
	if write:
		sb.write_png(os.path.join(OUT, folder, name + ".png"), pixels)
	print("  %s/%s.png  %dx%d" % (folder, name, len(pixels[0]), len(pixels)))


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(PACK):
		sys.exit("Cannot find the bullet art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(PACK))
	print("Bullets:")
	for folder, number in BULLETS.items():
		for name, pixels in directions(load(number), load(number + "_2")).items():
			save(folder, name, pixels, write)
	print("Boss round bullets:")
	_, _, ball = sb.read_png(BOSS_BALL)
	save("boss_bullet", "ball", recolor(ball, BOSS_BALL_COLORS), write)
	print("Grenades:")
	_, _, spin = sb.read_png(GRENADE)
	for folder, mapping in GRENADES.items():
		save(folder, "spin", recolor(spin, mapping), write)


if __name__ == "__main__":
	main()
