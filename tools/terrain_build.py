"""从地形素材包生成赛博朋克皮肤包的平台贴图和背景，输出到 skins/cyberpunk/terrain/ 和 skins/cyberpunk/backdrop/。

    python tools/terrain_build.py            # 全部重新生成
    python tools/terrain_build.py --check    # 只检查，不写文件

素材来源：CraftPix 的 Green Zone Tileset（art_in/default/green-zone-tileset/，不进仓库，授权和其它素材包一样）。
地砖每块 32×32，都在 Tileset.png 这一张图集里（12 列 × 8 行）。

**地形不换 TileMap**：关卡还是用 platform.tscn 搭，碰撞体和规则一点不动，只是外观按平台大小用
「九宫格」画——四个角原样、四条边和中间**平铺**（不拉伸，像素不会糊）。切法写在各自的外观场景里
（`TerrainAppearance` 的 left / right / top / bottom / hang），这里只负责把用到的地砖拼成一张源图：
- ground：草皮地面。只取中间那一列（上面草皮顶、下面紧接着它的土层），地面横贯整个关卡，
  两头的圆角会露在关卡边上，所以不要；地面厚过 32px 就往下铺土。
- ledge：浮空的单向平台。草顶、底边参差下垂的那一排（左 / 中 / 右）。平台只有 16px 厚，
  外观取顶上 10 行草面 + 底下 12 行（带下垂的碎块），下垂的部分挂在判定框下面 6px。
- stone：墙和矮通道的顶块。一整块四边带描边的石砖。**底边是平的**：矮通道只有 30px 净空，
  挂下垂碎块会让人以为钻不过去。

背景（`2 Background/Day`）五层都是 576×324：1 天空、2 远处楼群、3 远处树林、4 一条地面边、5 近处树林。
用白天那套：夜晚那套又灰又暗，黑描边的角色和子弹放上去看不清。视差和平铺由 `backdrop` 场景做。
**背景要往后退**：近处树林原本是 (55,68,110)，和石砖地形的深蓝 (34,42,92) 几乎一样，墙和矮通道顶块会融进背景里——
挡路挡子弹的东西必须一眼看出来。所以每层往地平线的天空色混一些（`HAZE`，越远混得越多，保留远近层次），
天空层原样。
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "green-zone-tileset")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk")
TILE = 32

# 源图：一排排地砖在图集里的 (行, 列)
TERRAIN = {
	"ground": [[(0, 1)], [(1, 1)]],
	"ledge": [[(4, 0), (4, 1), (4, 2)]],
	"stone": [[(2, 5)]],
}
BACKDROP = {"sky": "1", "buildings": "2", "trees_far": "3", "ground_line": "4", "trees_near": "5"}
## 装饰物（`3 Objects` / `4 Animated objects`）：名字 → (素材相对路径, 几帧)。
## **纯显示**，关卡里画在所有东西**后面**，绝不挡住敌人和子弹（规矩和特效一样）。
## 多帧的是横着一排的动画条（喷泉 288×72 = 4 帧），由 `Prop` 按 `region_rect` 逐帧播。
PROPS = {
	"tree_small": ("3 Objects/Other/Tree1.png", 1),
	"tree_big": ("3 Objects/Other/Tree2.png", 1),
	"bench": ("3 Objects/Benches/1.png", 1),
	"bench2": ("3 Objects/Benches/2.png", 1),
	"bin": ("3 Objects/Other/Garbage_Can1.png", 1),
	"box": ("3 Objects/Other/Box.png", 1),
	"fence": ("3 Objects/Fence/1.png", 1),
	"bush_big": ("3 Objects/Bushes/1.png", 1),
	"bush_wide": ("3 Objects/Bushes/17.png", 1),
	"bush_flat": ("3 Objects/Bushes/13.png", 1),
	"rock_small": ("3 Objects/Stones/2.png", 1),
	"rock": ("3 Objects/Stones/4.png", 1),
	"rock_big": ("3 Objects/Stones/6.png", 1),
	"grass_tuft": ("3 Objects/Grass/1.png", 1),
	"grass_blade": ("3 Objects/Grass/6.png", 1),
	"fountain": ("4 Animated objects/Fountain.png", 4),
}
## 背景素材只有 324 高，画面是 360——**地面线以下什么都没有**。平时地面盖着看不见，
## 但关卡里有坑之后，坑那一块就露出清屏色，看着像一块黑砖。
## 生成时把每层最底下那一行往下重复到这个高度，坑里看到的就是背景本身的延续。
BACKDROP_HEIGHT = 360
# 往天空色混多少（0 = 原样）。
HAZE_COLOR = (204, 226, 225)
HAZE = {"sky": 0.0, "buildings": 0.3, "trees_far": 0.4, "ground_line": 0.25, "trees_near": 0.25}


def haze(pixels, amount):
	if amount <= 0.0:
		return pixels
	return [[tuple(int(round(c[i] + (HAZE_COLOR[i] - c[i]) * amount)) for i in range(3)) + (c[3],) if c[3] > 8 else c
		for c in row] for row in pixels]


def extend_down(pixels, height):
	"""把最底下那一行往下重复到 height 高。素材只到地平线，坑里要露出背景的延续。"""
	if len(pixels) >= height:
		return pixels
	out = [list(row) for row in pixels]
	last = pixels[len(pixels) - 1]
	while len(out) < height:
		out.append(list(last))
	return out


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(PACK):
		sys.exit("找不到地形素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(PACK))
	_, _, atlas = sb.read_png(os.path.join(PACK, "Tileset.png"))
	print("地形：")
	for name, rows in TERRAIN.items():
		out = sb.blank(TILE * len(rows[0]), TILE * len(rows))
		for r, row in enumerate(rows):
			for c, (ty, tx) in enumerate(row):
				sb.blit(out, sb.cut(atlas, tx * TILE, ty * TILE, TILE, TILE), c * TILE, r * TILE, name)
		if write:
			sb.write_png(os.path.join(OUT, "terrain", name + ".png"), out)
		print("  terrain/%s.png  %dx%d" % (name, len(out[0]), len(out)))
	print("背景：")
	for name, number in BACKDROP.items():
		width, height, pixels = sb.read_png(os.path.join(PACK, "2 Background", "Day", number + ".png"))
		art = extend_down(haze(pixels, HAZE[name]), BACKDROP_HEIGHT)
		if write:
			sb.write_png(os.path.join(OUT, "backdrop", name + ".png"), art)
		print("  backdrop/%s.png  %dx%d（素材 %dx%d，往下补到画面底）  往天空色混 %d%%"
			% (name, len(art[0]), len(art), width, height, HAZE[name] * 100))
	print("装饰：")
	for name, (rel, frames) in sorted(PROPS.items()):
		source = os.path.join(PACK, *rel.split("/"))
		width, height, pixels = sb.read_png(source)
		if write:
			sb.write_png(os.path.join(OUT, "props", name + ".png"), pixels)
		print("  props/%s.png  %dx%d%s" % (name, width, height,
			"  %d 帧" % frames if frames > 1 else ""))


if __name__ == "__main__":
	main()
