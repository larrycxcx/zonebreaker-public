"""从素材包里挑子弹和手雷的贴图，生成赛博朋克皮肤包的发射物外观，输出到 skins/cyberpunk/projectiles/<名字>/。

    python tools/projectile_build.py            # 全部重新生成
    python tools/projectile_build.py --check    # 只检查，不写文件

素材来源：art_in/default/5 Bullets/（CraftPix，不进仓库）。每种子弹两张：`N.png` 水平朝右，`N_2.png` 斜 45°（朝右下）。
游戏里子弹只会朝 8 个方向飞，所以这里把每种子弹预先做成 8 张（right / left / up / down / up_right / ...），
`ProjectileAppearance` 按飞行方向挑一张——像素图不能在运行时转 45°，会糊。
手雷是圆的，只出一张 `ball.png`，不分方向。

挑哪张（`BULLETS` / `GRENADES`）：
- 玩家步枪：3 号，黄橙曳光弹——和占位时的黄色子弹一脉相承。
- 敌人（巡逻兵、Boss）：6 号，红白带黑描边，一眼能认出是敌人打的。
- 炮台：5 号，大颗青色等离子弹，和它绿色的机身配。
- E（无人机）：4 号，一根细细的青色激光，和它往下放的电一个颜色。
- 手雷：爆炸包（art_in/default/explosions/1 Bombs/）4 号，蓝绿色小罐子，本体 7×10，和 8px 的判定差不多大；
  它自带的 4 帧动画（`4_1.png`）是在空中翻滚，手雷飞行时循环播。F 打出来的那颗换成橙红色（`ENEMY_GRENADE_COLORS`），
  颜色都取自素材包自己的调色板。输出 `spin.png`：一排 4 帧 16×16。
- Boss A 的导弹扇形：boss 包 3 号自带的圆弹（12×8），换成红橙两色表示敌方。圆的不分方向，
  扇形可以打任意角度（像素图只有 8 个方向的话，20° 一发的扇形会画歪）。
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
	"""顺时针转 90°：朝右的子弹变成朝下。"""
	height, width = len(p), len(p[0])
	return [[p[height - 1 - x][y] for x in range(height)] for y in range(width)]


def directions(level, diagonal):
	"""水平（朝右）和斜向（朝右下）两张 → 8 个方向。"""
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
		sys.exit("找不到子弹素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(PACK))
	print("子弹：")
	for folder, number in BULLETS.items():
		for name, pixels in directions(load(number), load(number + "_2")).items():
			save(folder, name, pixels, write)
	print("Boss 的圆弹：")
	_, _, ball = sb.read_png(BOSS_BALL)
	save("boss_bullet", "ball", recolor(ball, BOSS_BALL_COLORS), write)
	print("手雷：")
	_, _, spin = sb.read_png(GRENADE)
	for folder, mapping in GRENADES.items():
		save(folder, "spin", recolor(spin, mapping), write)


if __name__ == "__main__":
	main()
