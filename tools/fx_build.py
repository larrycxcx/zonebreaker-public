"""从爆炸素材包生成赛博朋克皮肤包的特效贴图，输出到 skins/cyberpunk/fx/。

    python tools/fx_build.py            # 全部重新生成
    python tools/fx_build.py --check    # 只检查，不写文件

素材来源：CraftPix 的爆炸包（art_in/default/explosions/，不进仓库）。`3 Effects/` 下分四档尺寸
（Tiny 32、Low 48、Middle 72、High 96，每帧正方形），每档三种：1 绿色、2 红色 + 深蓝、3 闪电。
爆炸用 2 号（红 + 深蓝，8 帧）：四档都输出，`SpriteExplosion` 按爆炸半径挑最接近的一档 1:1 画——像素图不缩放。
"""
import os
import shutil
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "explosions", "3 Effects")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "fx")
SIZES = {32: "1 Tiny", 48: "2 Low", 72: "3 Middle", 96: "4 High"}
KIND = "2"  # 红 + 深蓝那种


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(PACK):
		sys.exit("找不到爆炸素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(PACK))
	print("爆炸：")
	for size, folder in SIZES.items():
		source = os.path.join(PACK, folder, KIND + ".png")
		width, height, _ = sb.read_png(source)
		assert height == size and width % size == 0, "%s 不是一排 %d×%d 的帧（%dx%d）" % (source, size, size, width, height)
		if write:
			os.makedirs(OUT, exist_ok=True)
			shutil.copyfile(source, os.path.join(OUT, "explosion_%d.png" % size))
		print("  fx/explosion_%d.png  %d 帧" % (size, width // size))


if __name__ == "__main__":
	main()
