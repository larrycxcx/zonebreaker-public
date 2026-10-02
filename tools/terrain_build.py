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
ART = os.path.join(HERE, "..", "art_in", "default")
SKINS = os.path.join(HERE, "..", "skins")
TILE = 32

## **一套地形素材 = 一个「区」**。加一关就往这张表里加一条，跑 `python tools/terrain_build.py industrial`。
## 地砖有两种取法，素材包怎么给就怎么取：
##   `atlas` 一张大图集，`terrain` 里写 (行, 列)；
##   `tiles` 一砖一个文件（带 `%d` 的模板），`terrain` 里写编号。
## `terrain` 的三个键是玩法认的（`platform.gd` 的 `skin_key`），不能改名：
##   `ground` 地面（横贯关卡，第二行往下铺）、`ledge` 浮空单向平台（一行三块：左中右）、`stone` 墙和堵块。
ZONES = {
	"cyberpunk": {
		"pack": "green-zone-tileset",
		"out": "cyberpunk",
		"atlas": "Tileset.png",
		"terrain": {"ground": [[(0, 1)], [(1, 1)]], "ledge": [[(4, 0), (4, 1), (4, 2)]], "stone": [[(2, 5)]]},
		"backdrop_dir": "2 Background/Day",
		"backdrop": {"sky": "1", "buildings": "2", "trees_far": "3", "ground_line": "4", "trees_near": "5"},
		"haze": {"sky": 0.0, "buildings": 0.3, "trees_far": 0.4, "ground_line": 0.25, "trees_near": 0.25},
		"props": {
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
		},
	},
	# 第三关：酒吧街。地砖是 100 个独立文件，**这套是「街景立面」不是地形包**——
	# 砖墙、窗、卷帘、遮阳棚，没有现成的「草皮地面」。所以挑的是：
	# 地面 = 带木梁顶的砖墙（02）压在素砖（05）上；浮台 = **遮阳棚**（07/08/09 左中右，
	# 在街上踩着店家的雨棚跳，正合这一关的题）；墙和堵块 = 卷帘门（59），
	# 灰蓝色和棕色砖地分得开，而且「拉下来的卷帘」本身就是「此路不通」的意思。
	# 背景用 **Night**，再加素材包自带的光照层（`Overlay_illumination.png`）——
	# Night 那几层本来就是灰的，是**留给光照层上色的**，宣传图那种粉 / 青霓虹就是这两样叠出来的。
	# （第一版只看了 Night 本身、嫌它灰，换成了 Day，和素材包的样子完全对不上。）
	# 人和子弹画在光照层上面（见 `ScreenLight`），不被染色，所以不会糊。
	"bar_street": {
		"pack": "bar-street-tileset",
		"out": "bar_street",
		"tiles": "1 Tiles/Tiles_%02d.png",
		"terrain": {"ground": [[2], [5]], "ledge": {"tiles": [[7, 8, 9]], "crop": 16},
			"stone": [[59]]},
		"backdrop_dir": "2 Background/Night",
		"backdrop": {"sky": "1", "far": "2", "mid": "3", "near": "4", "street": "5"},
		# 夜景不雾化：远近已经靠灰度分开了，往天空色混只会把光照层要染的那点明暗抹平
		"haze": {"sky": 0.0, "far": 0.0, "mid": 0.0, "near": 0.0, "street": 0.0},
		# 光照层的那张光斑。原图 1800×1200、整张都是糊的，缩一半看不出差别，仓库里省 3/4
		"lighting": ("2 Background/Overlay_illumination.png", 2),
		"facades": "BAR_FACADES",
		"props": {
			"counter": ("3 Objects/Bar counter/1.png", 1),
			"counter2": ("3 Objects/Bar counter/4.png", 1),
			"cabinet": ("3 Objects/Bar cabinet/1.png", 1),
			"cabinet2": ("3 Objects/Bar cabinet/5.png", 1),
			"stool": ("3 Objects/Bar stool/1.png", 1),
			"stool2": ("3 Objects/Bar stool/4.png", 1),
			"sign": ("3 Objects/Signboards/1.png", 1),
			"sign2": ("3 Objects/Signboards/3.png", 1),
			"crate": ("3 Objects/Props/Prop_01.png", 1),
			"keg": ("3 Objects/Props/Prop_06.png", 1),
			"bin": ("3 Objects/Props/Prop_11.png", 1),
			# 酒瓶、酒杯、飞钞、飘牌不要：摆在地上像能捡的东西（见 level_build.py 的 SCATTER_3）
		},
	},
	# 第二关：工业区。地砖是 81 个独立文件，编号 = 行 × 9 + 列 + 1。
	# **背景第 1 层是底色不是天空**：2 才是天空（只画到地平线 y=247），
	# 地平线以下露出第 1 层那片雾色，所以两层都不雾化。
	"industrial": {
		"pack": "industrial-zone-tileset",
		"out": "industrial",
		"tiles": "1 Tiles/IndustrialTile_%02d.png",
		# 薄条那三块只画了上半格，裁掉下面的空行，否则九宫格会把空白也当成边
		"terrain": {"ground": [[5], [14]], "ledge": {"tiles": [[77, 78, 79]], "crop": 16}, "stone": [[36]]},
		"backdrop_dir": "2 Background",
		"backdrop": {"base": "1", "sky": "2", "far": "3", "mid": "4", "near": "5"},
		"haze": {"base": 0.0, "sky": 0.0, "far": 0.62, "mid": 0.5, "near": 0.38},
		"props": {
			"barrel": ("3 Objects/Barrel1.png", 1),
			"barrel_rust": ("3 Objects/Barrel3.png", 1),
			"box": ("3 Objects/Box1.png", 1),
			"box_open": ("3 Objects/Box3.png", 1),
			"crate": ("3 Objects/Box7.png", 1),
			"board": ("3 Objects/Board1.png", 1),
			"fence": ("3 Objects/Fence1.png", 1),
			"fence_end": ("3 Objects/Fence3.png", 1),
			"ladder": ("3 Objects/Ladder1.png", 1),
			"locker": ("3 Objects/Locker1.png", 1),
			"extinguisher": ("3 Objects/Fire-extinguisher1.png", 1),
			"bench": ("3 Objects/Bench.png", 1),
			"bucket": ("3 Objects/Bucket.png", 1),
			"sign": ("3 Objects/Pointer1.png", 1),
			"flag": ("3 Objects/Flag.png", 1),
			"screen": ("4 Animated objects/Screen1.png", 4),
			"conveyor": ("4 Animated objects/Transporter1.png", 4),
		},
	},
}
# ---------------------------------------------------------------- 酒吧街的楼面
#
# 宣传图里街边那一排楼（砖墙、窗户、卷帘、雨棚）**素材包没给成品**，只给了拼楼用的砖（51~100 号
# 和右上那块蓝色条纹雨棚）。这里按配方拼成一栋一栋的整张图，输出成装饰（`props/facade_N.png`），
# 关卡生成时沿着地面摆在最后面（`level_build.py` 的 `facades`）——**纯显示**，和别的装饰一个规矩。
#
# 配方从上往下一行一格，格子之间空格分开，`+` 是叠上去（窗户 + 木板、砖墙 + 水管）。
# 字母表在 `FACADE_TILES`，`.` 是空的（楼顶参差不齐用）。最底下那行贴着地面。
#
# **楼上只用灰色波浪边的雨棚，不用蓝色条纹那种**：蓝条纹的是关卡里能踩的浮台（`ledge`），
# 楼面上也挂一排一模一样的，玩家分不清哪个能站（第一版截图一眼就看出来了）。
# 同理整张楼面**压暗一截**（`FACADE_SHADE`），让它退到能踩、能挡子弹的那些东西后面。
FACADE_SHADE = 0.75
FACADE_TILES = {
	"P": 76,                      # 楼顶女儿墙（自己能接自己）
	"B": 60, "c": 70, "k": 80, "x": 90, "z": 100,   # 砖墙，后四种带裂缝
	"W": 54, "C": 64, "T": 72, "D": 71, "S": 73, "N": 84, "E": 63,   # 窗：四格 / 窗帘 / 两格 / 黑 / 挂牌 / 纱窗 / 黑洞
	"-": 51, "_": 53,             # 楼层之间那条腰线 / 平墙
	"A": 97, "a": 98,             # 拱形门脸（挂着帘子）
	"U": 86, "u": 96, "O": 55, "o": 65,   # 卷帘 / 门（上下两格）
	"1": 81, "2": 82, "3": 83,    # 灰色波浪边雨棚（左中右）
	"b": 57, "d": 68,             # 钉在窗上的木板
	"#": 77, "%": 88,             # 防盗栏
	"i": 89, "l": 79,             # 水管
	"t": 91, "r": 93,             # 咖啡桌、椅子
}

BAR_FACADES = {
	"facade_1": [                 # 咖啡馆：雨棚、门口摆着桌子
		"P P P P P",
		"B W B C B",
		"k B T B c",
		"- - - - -",
		"B+1 E+2 E+2 E+2 B+3",
		"B A a+t A B",
	],
	"facade_2": [                 # 高的那栋：一侧挂水管，有几扇钉了木板
		". P P P .",
		"P B B B P",
		"B+i W C+# W+b B",
		"B+i T B W x",
		"c+i W+d B C B",
		"- - - - -",
		"B+i U u U B",
	],
	"facade_3": [                 # 窄的小酒吧：灰雨棚
		"P P P",
		"B S B",
		"_ W _",
		"B+1 B+2 B+3",
		"B A B",
	],
	"facade_4": [                 # 关了门的铺子：卷帘、防盗栏
		"P P P P P P",
		"B D+% B D+# B z",
		"k B W+b B W k",
		"- - - - - -",
		"B U u U u B",
	],
	"facade_5": [                 # 一楼是门脸、楼上是公寓
		". . P P P P",
		"P P B C B B",
		"B W B T B+i x",
		"B C k W B+i B",
		"- - - - - -",
		"B+1 N+2 O+2 N+2 N+2 B+3",
		"B N o+r N A B",
	],
	"facade_6": [                 # 矮墙一截，楼与楼之间的空当
		"P P P P",
		"B c B+l k",
		"B T B+l W",
		"B+1 B+2 B+2 B+3",
		"B A a B",
	],
}


## 背景素材只有 324 高，画面是 360——**地面线以下什么都没有**。平时地面盖着看不见，
## 但关卡里有坑之后，坑那一块就露出清屏色，看着像一块黑砖。
## 生成时把每层最底下那一行往下重复到这个高度，坑里看到的就是背景本身的延续。
BACKDROP_HEIGHT = 360
# 往天空色混多少（0 = 原样）。两套素材的天空是同一个色。
HAZE_COLOR = (204, 226, 225)


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


def load_tile(zone, pack, atlas, spec):
	"""取一块地砖。图集那种 `spec` 是 (行, 列)，一砖一文件那种是编号。"""
	if atlas is not None:
		ty, tx = spec
		return sb.cut(atlas, tx * TILE, ty * TILE, TILE, TILE)
	_, _, pixels = sb.read_png(os.path.join(pack, *(zone["tiles"] % spec).split("/")))
	return pixels


def build_zone(key, write):
	zone = ZONES[key]
	pack = os.path.join(ART, zone["pack"])
	out = os.path.join(SKINS, zone["out"])
	if not os.path.isdir(pack):
		sys.exit("找不到地形素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(pack))
	atlas = None
	if "atlas" in zone:
		_, _, atlas = sb.read_png(os.path.join(pack, zone["atlas"]))
	print("== %s（%s）==" % (key, zone["pack"]))
	print("地形：")
	for name, spec in zone["terrain"].items():
		rows = spec["tiles"] if isinstance(spec, dict) else spec
		art = sb.blank(TILE * len(rows[0]), TILE * len(rows))
		for r, row in enumerate(rows):
			for c, tile in enumerate(row):
				sb.blit(art, load_tile(zone, pack, atlas, tile), c * TILE, r * TILE, name)
		if isinstance(spec, dict) and "crop" in spec:
			art = art[: spec["crop"]]
		if write:
			sb.write_png(os.path.join(out, "terrain", name + ".png"), art)
		print("  terrain/%s.png  %dx%d" % (name, len(art[0]), len(art)))
	print("背景：")
	for name, number in zone["backdrop"].items():
		source = os.path.join(pack, *zone["backdrop_dir"].split("/"), number + ".png")
		width, height, pixels = sb.read_png(source)
		art = extend_down(haze(pixels, zone["haze"][name]), BACKDROP_HEIGHT)
		if write:
			sb.write_png(os.path.join(out, "backdrop", name + ".png"), art)
		print("  backdrop/%s.png  %dx%d（素材 %dx%d，往下补到画面底）  往天空色混 %d%%"
			% (name, len(art[0]), len(art), width, height, zone["haze"][name] * 100))
	if "lighting" in zone:
		rel, shrink = zone["lighting"]
		width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
		art = [[pixels[y][x] for x in range(0, width, shrink)] for y in range(0, height, shrink)]
		if write:
			sb.write_png(os.path.join(out, "lighting", "glow.png"), art)
		print("光照：")
		print("  lighting/glow.png  %dx%d（素材 %dx%d）" % (len(art[0]), len(art), width, height))
	if "facades" in zone:
		print("楼面：")
		for name, recipe in globals()[zone["facades"]].items():
			art = facade(zone, pack, recipe)
			if write:
				sb.write_png(os.path.join(out, "props", name + ".png"), art)
			print("  props/%s.png  %dx%d" % (name, len(art[0]), len(art)))
	print("装饰：")
	for name, (rel, frames) in sorted(zone["props"].items()):
		width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
		if write:
			sb.write_png(os.path.join(out, "props", name + ".png"), pixels)
		print("  props/%s.png  %dx%d%s" % (name, width, height,
			"  %d 帧" % frames if frames > 1 else ""))


def facade(zone, pack, recipe):
	"""按配方拼一栋楼：一格一块砖，`+` 叠上去，`.` 空着。"""
	rows = [line.split() for line in recipe]
	wide = len(rows[0])
	for r, row in enumerate(rows):
		if len(row) != wide:
			sys.exit("楼面配方第 %d 行有 %d 格，别的行是 %d 格" % (r + 1, len(row), wide))
	art = sb.blank(TILE * wide, TILE * len(rows))
	for r, row in enumerate(rows):
		for c, cell in enumerate(row):
			if cell == ".":
				continue
			for part in cell.split("+"):
				if part not in FACADE_TILES:
					sys.exit("楼面配方里有不认识的字母：%s" % part)
				tile = load_tile(zone, pack, None, FACADE_TILES[part])
				sb.blit(art, tile, c * TILE, r * TILE, "facade")
	return [[tuple(int(round(p[i] * FACADE_SHADE)) for i in range(3)) + (p[3],) for p in row] for row in art]


def main():
	write = "--check" not in sys.argv
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	for key in (only if only else ZONES):
		if key not in ZONES:
			sys.exit("没有这个区：%s（有的是 %s）" % (key, ", ".join(ZONES)))
		build_zone(key, write)


if __name__ == "__main__":
	main()
