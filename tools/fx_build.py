"""从爆炸包和枪口效果素材生成赛博朋克皮肤包的特效贴图，输出到 skins/cyberpunk/fx/。

    python tools/fx_build.py            # 全部重新生成
    python tools/fx_build.py --check    # 只检查，不写文件

素材来源（CraftPix，都不进仓库）：
- 爆炸包 `art_in/default/explosions/3 Effects/`：四档尺寸（Tiny 32、Low 48、Middle 72、High 96，每帧正方形），
  每档三种（1 绿、2 红 + 深蓝、3 闪电）。
  - **手雷爆炸**用 2 号，四档都输出（`explosion_<边长>.png`），`SpriteExplosion` 按半径挑最接近的一档 1:1 画。
  - **打中角色的火花**用 Tiny 档 2 号（`hit.png`，32×32 × 8 帧）：一小团红色爆炸，一看就是挨打了。
- 角色包 `art_in/default/4 Shoot_effects/`：白色剪影，每种有水平（`_1`）和斜 45°（`_2`）两张，各 6 帧 48×48，
  从格子左边缘（枪口）往右 / 右下喷。颜色在场景里用 `tint` 染。
  - **枪口闪光**用 9 号（一团带火星的爆闪）。
  - **子弹打在墙上**用 6 号（细碎的四散火星），朝子弹飞来的方向溅回去。
  像素图不能在运行时转 45°，所以和子弹一样预先做成 8 个方向（`<名字>/<方向>.png`）。每张先挪进 96×96 的格子，
  让**喷出点（枪口）正好在格子中心**——水平那张在原格子 (0, 24)，斜向那张在 (0, 0)——其余方向绕中心翻转 / 旋转，
  特效的原点就是枪口，放在哪都不偏。
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
BLASTS = os.path.join(HERE, "..", "art_in", "default", "explosions", "3 Effects")
SHOTS = os.path.join(HERE, "..", "art_in", "default", "4 Shoot_effects")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "fx")
SIZES = {32: "1 Tiny", 48: "2 Low", 72: "3 Middle", 96: "4 High"}
KIND = "2"  # 红 + 深蓝那种

SHOT_CELL = 48
CELL = 96
CENTER = CELL // 2
# 喷出点在原格子里的位置：水平那张、斜向那张
LEVEL_ORIGIN = (0, 24)
DIAGONAL_ORIGIN = (0, 0)
# 名字 → 用哪号枪口效果
DIRECTIONAL = {"muzzle": 9, "impact": 6}
# 方向名 → (用水平还是斜向那张, 把相对喷出点的 (dx, dy) 变到这个方向)
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
			sys.exit("找不到特效素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(folder))
	print("爆炸：")
	for size, folder in SIZES.items():
		width, height, pixels = sb.read_png(os.path.join(BLASTS, folder, KIND + ".png"))
		assert height == size and width % size == 0, "%s/%s.png 不是一排 %d×%d 的帧" % (folder, KIND, size, size)
		if write:
			sb.write_png(os.path.join(OUT, "explosion_%d.png" % size), pixels)
		print("  fx/explosion_%d.png  %d 帧" % (size, width // size))
	print("打中角色的火花：")
	width, _, pixels = sb.read_png(os.path.join(BLASTS, "1 Tiny", KIND + ".png"))
	if write:
		sb.write_png(os.path.join(OUT, "hit.png"), pixels)
	print("  fx/hit.png  %d 帧" % (width // 32))
	for name, number in DIRECTIONAL.items():
		print("%s（枪口效果 %d 号）：" % (name, number))
		for direction, strip, frames in directional(number, write):
			if write:
				sb.write_png(os.path.join(OUT, name, direction + ".png"), strip)
			print("  fx/%s/%s.png  %d 帧" % (name, direction, frames))


if __name__ == "__main__":
	main()
