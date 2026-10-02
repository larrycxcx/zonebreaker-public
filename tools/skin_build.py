"""从原始素材包生成赛博朋克皮肤包的玩家贴图，一个角色一个目录（skins/cyberpunk/biker、punk、cyborg）。

    python tools/skin_build.py            # 三个角色都重新生成
    python tools/skin_build.py cyborg     # 只生成一个
    python tools/skin_build.py --check    # 只检查有没有内容被画布切掉，不写文件

素材来源是 CraftPix 那套「Free Guns for Cyberpunk Characters」，解压在 art_in/default/
（不进仓库，授权禁止再分发源文件）。这个脚本做三件事：

1. **脱掉身体自带的手臂**：瞄准的手臂是单独贴上去的，身体不能再带一副。
   素材里 `*2.png` 本来就是脱好的（Walk2 / Run2 / Jump2），但 Dash、Idle1 这些没有无手臂版，
   所以统一过一道 `strip_arms()`，本来就没手臂的一个像素都不会动。
2. **按肩膀对齐**：素材每帧 48×48，但奔跑/跳跃那几组角色整体往右画了约 6px（前倾）。
   手臂是按站立时的肩膀位置画的，照搬就会和跑动的身体脱节。
   所以每一帧都按**躯干中心**重新对齐，手臂就能固定在一个位置、不用跟着每帧动。
3. **合成手臂**：一个瞄准方向 = 后手臂 + 枪 + 前手臂 三层叠在一起（顺序不能变：
   后手臂在枪后面、前手臂在枪前面），烘成一张图。

输出的每帧是 56×56，**锚点（贴图上对应角色身体原点的那个点）在 (28, 40)**：
横向是躯干中心，纵向让脚底落在原点下方 16px（和玩家 32px 高的碰撞体对上）。
朝左的图是**按锚点所在的那一列镜像**出来的，所以左右两套图的锚点完全重合，
运行时不需要 flip_h、也不用负的 scale（负 scale 会让角色被错误剔除，见 CLAUDE.md 踩过的坑）。
"""
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "art_in", "default")
OWN = os.path.join(HERE, "..", "art_src")
SKIN = os.path.join(HERE, "..", "skins", "cyberpunk")

# 皮肤键 → 素材里的角色。**键就是角色名，不是「1 号玩家 / 2 号玩家」**：
# 外观是角色自己的属性（存在档案里），2 号玩家照样可以选 Biker。
# 三个角色在素材包里规格完全一样（48×48、同样的 10 张手臂、同一套动作名），所以除了名字什么都不用改。
# 死亡动画各自在自己的文件夹里（`<角色>_death.png`）。
CHARACTERS = {
	"biker": "1 Biker",
	"punk": "2 Punk",
	"cyborg": "3 Cyborg",
}

# 下面这三个是「当前正在生成哪个角色」，由 use_character() 切换。
# 做成全局而不是一路往下传参数：这个脚本从头到尾都在处理同一个角色，
# 每个函数多一个参数只会让本来就长的调用链更难读。
CHARACTER = ""
KEY = ""
OUT = ""
DEATH = ""
# 每种枪的外观用素材包里哪一把（`2 Guns/` 里的编号）。键就是 `Weapon.look`，
# 每把输出一整套手臂贴图 `arms_<外观>_<方向>_<朝向>.png`，玩家切武器时外观层换一套。
# **别挑太小的枪**：素材里的后手臂是按「大部分被枪挡住」画的，1 号枪只有 26×7，
# 斜射时那条粗胳膊会整根露在枪外面，看着像身上挂了根香肠。
#   rifle    步枪，4 号（29×11）
#   launcher 榴弹枪（扔手雷那把），5 号（28×16）：粗炮管一眼就和步枪分得开，长度又和步枪差不多。
#            两把枪共用一套出膛点（玩法规则），5 号的枪口和出膛点最多差 2.8px，见 test_cyberpunk_skin.gd。
GUNS = {"rifle": 4, "launcher": 5}

CELL = 48          # 素材每帧的边长
ARM_CELL = 32      # 手臂/枪格子的边长
# 手臂格子放在角色帧里的位置。横向居中，**纵向要往下 3px**：
# 居中（8, 8）看着自然，其实没依据——那样胳膊会从脖子上长出来、枪管落在身高的 74%。
# 肩膀的真实位置是量出来的：`Idle1` 减 `Idle2` 差出来的就是素材自带的胳膊，它的根部在帧内 y=26~28；
# 前手臂（`8.png`）的根部在格子内 y≈16，所以格子要放在 y=11 上，根部才落到 27。
# 这么放之后枪管在身高的 66%，和素材包宣传图里那只握枪的手一致（量出来 64%）。
ARM_INSET_X = (CELL - ARM_CELL) // 2
ARM_INSET_Y = 11
FRAME = 56         # 输出帧的边长
ANCHOR = (28, 40)  # 输出帧里对应角色身体原点的那个点
# 素材帧里锚点的高度：脚底在帧底边（y=48），要落在身体原点下方 16px。
SRC_ANCHOR_Y = CELL - 16
TORSO_ROWS = (14, 30)   # 量躯干中心时只看这几行（头 + 上半身），腿在跑动时会甩开
# 手臂素材是按站立姿势的肩膀画的，对应 Idle 的躯干中心。
ARM_BASELINE = 13.0

# 身体动画：输出名 → (素材文件, 取哪几帧)。
# **air 只有一帧**：整个空中（上升、最高点、下落）都保持同一个姿势。
# 本来是两帧、按纵向速度切，但在最高点换图那一下看着很别扭（2026-09 试玩），
# 很多横版射击本来也就一个滞空姿势。`SpriteAppearance` 取下落那帧时会夹到最后一帧，所以一帧也照常工作。
# crouch 取下蹲循环里压得最低的那一帧。
#
# **走路用的是素材里的「跑」、冲刺用的是「Dash」**（2026-09 试玩后改的，嫌节奏慢）：
# 速度一个数都没动，只是换了贴图——正常移动看着就是在跑，按住冲刺再加一层残影。
# 素材包里只有 `*2.png` 是脱了手臂的（留给我们贴瞄准手臂），Dash、Idle1 这些都带着手臂，
# 所以生成时统一过一道 `strip_arms()`：本来就没手臂的（Walk2/Run2/Jump2）一个像素都不会动。
BODIES = {
	"idle": ("Idle1", [0, 1, 2, 3]),
	"walk": ("Run2", [0, 1, 2, 3, 4, 5]),
	"run": ("Dash", [0, 1, 2, 3, 4, 5]),
	"air": ("Jump2", [1]),
}

# 裸露的胳膊用的两种颜色（亮面 + 暗面）。脸和脖子也是这两种颜色，所以不能按颜色一刀切，
# 要按连通块来分：脸那一块在 y=19~25，胳膊那几块基本都从 y=26 往下开始。
SKIN_COLORS = {(163, 109, 62), (104, 60, 52)}
ARM_TOP = 26       # 连通块的最高点在这一行或更下面，才算胳膊
# 再小就不是胳膊了：无手臂版里也会有一两个零散的肤色像素（拳头的一角之类），
# 不设这个下限的话它们会被当成胳膊删掉，「本来就无手臂的图一个像素都不动」这条就不成立了。
ARM_MIN = 6
# 举到胸口的那条胳膊会和脖子连在一起，整块从 y=24 就开始，卡不住上面那条线。
# 它的特征是**又粗又长**：脸和脖子再大也垂不到 ARM_DEEP 那么低。
ARM_BIG = 20
ARM_DEEP = 30
OUTLINE = (0, 0, 0)
# Dash 那几帧身后的速度残影。它横着铺出去老远，量躯干中心时要先把它排除掉，否则整个人会被推偏。
STREAK = (255, 246, 174)

# 死亡动画来自 CraftPix 同系列的另一个包（第三方素材，和 art_in/default 一样不进仓库），
# 格式和素材包完全一致：一排 6 帧 × 48×48，第 1 帧就是空手站立的 Idle1。
# **从第 2 帧开始用**：第 1 帧是空手站着，从它播会先出现「枪突然没了、人愣一下」的一拍；
# 从开始后仰那帧播，枪消失的那一下被倒地的动作盖住。
# **不按躯干逐帧对齐**：人是往后倒的，逐帧把躯干拉回原点会把后倒的位移抵消掉，变成原地打转。
# 所以整组只按第 1 帧（站立）的躯干定一次位，后面几帧保留画师原本的摆位。
DEATH_FRAMES = [1, 2, 3, 4, 5]

# 趴下和爬行**不在素材包里**（CraftPix 那套只有单膝跪姿），是自己画的，放在 art_src/（进仓库）。
# `biker_prone.png` 是**原生分辨率**的一排四帧（约 43×14 一帧，帧与帧之间隔着空列），1:1 使用、不缩放。
# 原图是按 9 倍放大、再存成有损 webp 交过来的，按 9px 的网格逐格取中间那点的众数还原回来的；
# 以后再补图，**直接导出 1 倍大小的 PNG**，就不用再做这一步。
# **高度是有规矩的**：每一帧都要藏在敌人站着开枪的子弹下面，又要和 12px 的判定框差不多高，
# test_cyberpunk_skin.gd 逐帧守着。
## 每个角色一张趴姿 / 爬行源图，外加**这张图上躯干是什么颜色**——四帧按躯干中心对齐时要认它。
## 没列出来的角色回落到 biker 那张（`restyle()` 会把颜色贴到它自己的调色板上）。
##
## **躯干得按颜色认，通用办法不好使**：试过按外框右缘（头）、按整体重心、按「帧之间重叠最多」
## 对齐，拿 biker 那组当标准比，三种都差 2~3px——那足够看出来人在原地前后滑。
## 画师在图里表达的就是「这一块不动」，只能照着认。
## 挑哪个颜色**按「哪一块最不动」挑**（量出来的滑动量，越小越好）：
##   biker  上衣的粉（手画原图、没贴过调色板，同一片粉有几十种近似色，所以容差给得大）滑 3.0px
##   punk   深蓝上衣 0.6px（头发也是粉的，按 biker 那套认会认到头上去）
##   cyborg 绿头发 1.7px。连体服整件一个颜色分不出上衣；腰上那条深紫试过，滑 4.5px 最差，
##          而且它在身子偏后，按它对齐会把整个人推出 56px 的画布
## 最后一个数是**这个标记该落在原点前方几像素**，定的是整组摆在哪；
## 按「四帧的外框中心平均落在原点上」取，三个角色因此站得一样正。
PRONE_ART = {
	"biker": ("biker_prone.png", (252, 60, 95), 80, 5),
	"punk": ("punk_prone.png", (55, 68, 110), 40, 3),
	"cyborg": ("cyborg_prone.png", (21, 137, 104), 40, 12),
}
PRONE = "biker_prone.png"
PRONE_TORSO = (252, 60, 95)
PRONE_TOLERANCE = 80
PRONE_STILL = 1              # 趴着不动用第几帧（从 0 数）
PRONE_CRAWL = [0, 1, 2, 3]   # 爬行循环用哪几帧、什么顺序：腿伸直 → 收膝 → 再伸直
# 四帧按**上衣（躯干）中心**对齐：爬的时候前半身基本不动、腿往上收，按躯干对齐人才不会原地前后滑。
# 躯干放在身体原点前方 5px，这样静止那帧整体大致对着原点（头在前、脚在后，头短脚长）。
PRONE_TORSO_X = 5   # 由 PRONE_ART 按角色覆盖

# 瞄准方向 → (手臂编号, 用哪张枪, 是否上下翻转, 旋转角度, 握枪那只手在 32×32 格子里的位置, 子弹飞的方向)。
# 手臂 1~5 是后手臂（画在枪后面），6~10 是同样 5 个方向的前手臂（画在枪前面）。
# 枪只有水平（`_1`）和斜下 45°（`_2`）两张：斜上是把斜下那张上下翻过来，正上/正下是把水平那张转 90°。
#
# **枪放在哪里由「手在哪里」决定，不要自己推**：素材里手臂不是绕一个固定点转的，
# 画师每个方向都把整条胳膊挪了位置，按「握把固定在格子中心」推出来的落点五个方向里错四个。
# 手的位置是从 Hands.psd 量的：前手臂那组里的 `Deep_shadows` 图层就是从枪另一侧露出来的那只手。
# **正下方那张是例外**：它没有这块小方块。那个姿势两条胳膊是两根平行的竖棒，
# 一根在身体前面（`6.png`，格子 x1..7）、一根在身体外侧（`1.png`，x14..19），
# **枪夹在两者中间**（x≈11），不是挂在任何一条上——按后手臂末端放会让枪整个飘到身体外面。
AIMS = {
	"down":      (1, "1", False,  90, (11.0, 25.0), (0, 1)),
	"diag_down": (2, "2", False,   0, (14.5, 24.0), (1, 1)),
	"level":     (3, "1", False,   0, (19.5, 17.0), (1, 0)),
	"diag_up":   (4, "2", True,    0, (19.0, 5.5), (1, -1)),
	"up":        (5, "1", False, -90, (16.0, 2.5), (0, -1)),
}

# 前握把在枪身上的位置：从枪托那头算起 66% 处，再往枪管下方挪 1px。
# 这两个数是按水平那张（唯一一眼就能看出对不对的）量出来的，其它方向沿用同一套。
GRIP_ALONG = 0.66
GRIP_ACROSS = 1.0

_clipped = []


# ---------------------------------------------------------------- PNG 读写

def read_png(path):
	data = open(path, "rb").read()
	assert data[:8] == b"\x89PNG\r\n\x1a\n", path
	pos, idat, width, height, depth, color, palette, trns = 8, b"", 0, 0, 0, 0, None, None
	while pos < len(data):
		length = struct.unpack(">I", data[pos:pos + 4])[0]
		tag = data[pos + 4:pos + 8]
		chunk = data[pos + 8:pos + 8 + length]
		if tag == b"IHDR":
			width, height, depth, color = struct.unpack(">IIBB", chunk[:10])
		elif tag == b"IDAT":
			idat += chunk
		elif tag == b"PLTE":
			palette = chunk
		elif tag == b"tRNS":
			trns = chunk
		pos += 12 + length
	assert depth == 8, "只处理 8 位色深：%s" % path
	channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
	raw = zlib.decompress(idat)
	stride = width * channels
	rows, prev, pos = [], bytes(stride), 0
	for _ in range(height):
		filter_type = raw[pos]
		line = bytearray(raw[pos + 1:pos + 1 + stride])
		pos += 1 + stride
		for i in range(stride):
			a = line[i - channels] if i >= channels else 0
			b = prev[i]
			c = prev[i - channels] if i >= channels else 0
			if filter_type == 1:
				line[i] = (line[i] + a) & 255
			elif filter_type == 2:
				line[i] = (line[i] + b) & 255
			elif filter_type == 3:
				line[i] = (line[i] + (a + b) // 2) & 255
			elif filter_type == 4:
				p = a + b - c
				pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
				pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
				line[i] = (line[i] + pr) & 255
		rows.append(bytes(line))
		prev = rows[-1]

	pixels = []
	for line in rows:
		row = []
		for x in range(width):
			px = line[x * channels:(x + 1) * channels]
			if color == 6:
				row.append(tuple(px))
			elif color == 2:
				row.append((px[0], px[1], px[2], 255))
			elif color == 3:
				i = px[0]
				r, g, b = palette[i * 3:i * 3 + 3]
				row.append((r, g, b, trns[i] if trns and i < len(trns) else 255))
			elif color == 4:
				row.append((px[0], px[0], px[0], px[1]))
			else:
				row.append((px[0], px[0], px[0], 255))
		pixels.append(row)
	return width, height, pixels


def write_png(path, pixels):
	height, width = len(pixels), len(pixels[0])
	raw = bytearray()
	for row in pixels:
		raw.append(0)
		for r, g, b, a in row:
			raw += bytes((r, g, b, a))

	def chunk(tag, data):
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

	out = b"\x89PNG\r\n\x1a\n"
	out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
	out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
	out += chunk(b"IEND", b"")
	os.makedirs(os.path.dirname(path), exist_ok=True)
	open(path, "wb").write(out)


# ---------------------------------------------------------------- 画布操作

def blank(width, height):
	return [[(0, 0, 0, 0)] * width for _ in range(height)]


def blit(dst, src, ox, oy, where):
	"""把 src 叠到 dst 的 (ox, oy)。有内容落在画布外就记下来，最后统一报。"""
	height, width = len(dst), len(dst[0])
	for y, row in enumerate(src):
		for x, color in enumerate(row):
			if color[3] <= 8:
				continue
			dy, dx = oy + y, ox + x
			if 0 <= dy < height and 0 <= dx < width:
				dst[dy][dx] = color
			else:
				_clipped.append("%s：像素 (%d, %d) 落在 %dx%d 画布外" % (where, dx, dy, width, height))


def cut(pixels, x0, y0, width, height):
	return [row[x0:x0 + width] for row in pixels[y0:y0 + height]]


def rotate(src, degrees):
	if degrees == 0:
		return src
	height, width = len(src), len(src[0])
	if degrees == 90:    # 顺时针：朝右 → 朝下
		return [[src[height - 1 - x][y] for x in range(height)] for y in range(width)]
	if degrees == -90:   # 逆时针：朝右 → 朝上
		return [[src[x][width - 1 - y] for x in range(height)] for y in range(width)]
	raise ValueError(degrees)


def mirror(src):
	"""按锚点所在的那一列左右镜像，锚点自己不动。"""
	width = len(src[0])
	out = blank(width, len(src))
	for y, row in enumerate(src):
		for x, color in enumerate(row):
			sx = 2 * ANCHOR[0] - x
			if color[3] > 8 and 0 <= sx < width:
				out[y][sx] = color
	return out


# ---------------------------------------------------------------- 生成

def strip_arms(frame):
	"""把素材自带的裸露胳膊去掉，留出位置给瞄准手臂。已经是无手臂版的，一个像素都不会动。

	按颜色一刀切不行——脸和脖子和胳膊是同一种肤色。所以先把肤色像素分成连通块，
	**只丢掉从 ARM_TOP 以下才开始的那几块**（脸在更上面），再把只挨着这几块、
	不挨任何别的身体颜色的黑描边一起丢掉（那是胳膊自己的轮廓）。
	"""
	size = len(frame)
	skin = {(x, y) for y in range(size) for x in range(size)
		if frame[y][x][3] > 8 and frame[y][x][:3] in SKIN_COLORS}
	arms, seen = set(), set()
	for start in sorted(skin):
		if start in seen:
			continue
		stack, blob = [start], []
		seen.add(start)
		while stack:
			x, y = stack.pop()
			blob.append((x, y))
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				near = (x + dx, y + dy)
				if near in skin and near not in seen:
					seen.add(near)
					stack.append(near)
		top = min(point[1] for point in blob)
		bottom = max(point[1] for point in blob)
		big_and_low = len(blob) >= ARM_BIG and bottom >= ARM_DEEP
		if len(blob) >= ARM_MIN and (top >= ARM_TOP or big_and_low):
			arms |= set(blob)
	out = [list(row) for row in frame]
	for x, y in arms:
		out[y][x] = (0, 0, 0, 0)
	for y in range(size):
		for x in range(size):
			if frame[y][x][3] <= 8 or frame[y][x][:3] != OUTLINE:
				continue
			touches_arm = touches_body = False
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if not (0 <= nx < size and 0 <= ny < size) or frame[ny][nx][3] <= 8:
						continue
					if (nx, ny) in arms:
						touches_arm = True
					elif frame[ny][nx][:3] != OUTLINE:
						touches_body = True
			if touches_arm and not touches_body:
				out[y][x] = (0, 0, 0, 0)
	return out


def torso_center(frame):
	"""这一帧躯干（头 + 上半身）的横向中心。手臂就贴在这个位置上。"""
	left = right = None
	for y in range(TORSO_ROWS[0], TORSO_ROWS[1] + 1):
		for x, color in enumerate(frame[y]):
			if color[3] > 8 and color[:3] != STREAK:
				left = x if left is None else min(left, x)
				right = x if right is None else max(right, x)
	assert left is not None, "这一帧的躯干是空的"
	return (left + right) / 2.0


def place(content, anchor_x, where):
	"""把 48×48 的内容放进 56×56 的输出帧：anchor_x 那一列对准锚点，脚底对准原点下方 16px。"""
	out = blank(FRAME, FRAME)
	blit(out, content, ANCHOR[0] - int(round(anchor_x)), ANCHOR[1] - SRC_ANCHOR_Y, where)
	return out


def palette():
	"""角色自己的调色板，按用得多的排前面。自己画的图要贴回这套颜色，免得和素材包其它帧不搭。"""
	_, _, pixels = read_png(os.path.join(SRC, "1 Characters", CHARACTER, "Idle1.png"))
	seen = {}
	for row in pixels:
		for color in row:
			if color[3] > 8:
				seen[color[:3]] = seen.get(color[:3], 0) + 1
	return sorted(seen, key=lambda c: -seen[c])


def prone_frames():
	"""把自己画的那排趴姿按空列切成一帧一帧（原生分辨率，不缩放）。"""
	_, _, pixels = read_png(os.path.join(OWN, PRONE))
	width = len(pixels[0])
	solid = [any(row[x][3] > 8 for row in pixels) for x in range(width)]
	frames, start = [], None
	for x in range(width + 1):
		on = x < width and solid[x]
		if on and start is None:
			start = x
		elif not on and start is not None:
			frames.append(cut(pixels, start, 0, x - start, len(pixels)))
			start = None
	return frames


def restyle(art, colors):
	"""贴回角色自己的调色板，**外轮廓那圈深色换成纯黑**——素材包所有角色的描边都是黑的，
	自己画的是深紫，贴完调色板会落到头发那个颜色上，和站姿放在一起描边颜色对不上。"""
	height, width = len(art), len(art[0])
	out = []
	for row in art:
		out.append([(0, 0, 0, 0) if c[3] <= 8 else
			min(colors, key=lambda p: sum((p[i] - c[i]) ** 2 for i in range(3))) + (255,) for c in row])
	result = [row[:] for row in out]
	for y in range(height):
		for x in range(width):
			c = out[y][x]
			if c[3] == 0:
				continue
			edge = any(not (0 <= y + dy < height and 0 <= x + dx < width) or out[y + dy][x + dx][3] == 0
				for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
			if edge and 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] < 45:
				result[y][x] = (0, 0, 0, 255)
	return result


def torso_x(art):
	"""躯干（`PRONE_TORSO` 那个颜色，容差 `PRONE_TOLERANCE`）的横向中心。

	**要在贴调色板之前量**：贴完某个角色的调色板，这个颜色可能一点都不剩，
	那时候按颜色找就什么也找不到。对齐是画出来的事，和换成谁的颜色无关。
	"""
	limit = PRONE_TOLERANCE ** 2
	xs = [x for row in art for x, c in enumerate(row)
		if c[3] and sum((c[i] - PRONE_TORSO[i]) ** 2 for i in range(3)) <= limit]
	if not xs:
		raise SystemExit("%s：在 %s 上找不到躯干那个颜色 %s，PRONE_ART 里的数字要跟着素材改"
			% (CHARACTER, PRONE, PRONE_TORSO))
	return sum(xs) / len(xs)


def place_prone(art, where, middle):
	"""`middle` 是这一帧上衣的横向中心，从**没贴调色板的原图**上量（见 torso_x）。"""
	frame = blank(FRAME, FRAME)
	bottom = max(y for y, row in enumerate(art) if any(c[3] for c in row))
	# 躯干对准原点前方 PRONE_TORSO_X，最低那一行落在原点下方 16px（和站姿同一条地面线）
	blit(frame, art, ANCHOR[0] + PRONE_TORSO_X - int(round(middle)), ANCHOR[1] + 16 - 1 - bottom, where)
	return frame


def build_death(write):
	_, _, pixels = read_png(DEATH)
	standing = cut(pixels, 0, 0, CELL, CELL)
	anchor_x = torso_center(standing)       # 只量一次，整组共用
	right = [place(cut(pixels, i * CELL, 0, CELL, CELL), anchor_x, "death 第%d帧" % (i + 1)) for i in DEATH_FRAMES]
	save_strip("body_death_r.png", right, write)
	save_strip("body_death_l.png", [mirror(f) for f in right], write)


def build_prone(write):
	colors = palette()
	source = prone_frames()
	middles = [torso_x(f) for f in source]      # 在原图上量，贴完调色板就量不着了
	frames = [restyle(f, colors) for f in source]
	still = [place_prone(frames[PRONE_STILL], "crouch", middles[PRONE_STILL])]
	crawl = [place_prone(frames[i], "crawl 第%d帧" % (i + 1), middles[i]) for i in PRONE_CRAWL]
	save_strip("body_crouch_r.png", still, write)
	save_strip("body_crouch_l.png", [mirror(f) for f in still], write)
	save_strip("body_crawl_r.png", crawl, write)
	save_strip("body_crawl_l.png", [mirror(f) for f in crawl], write)


## 自己补的无臂版在哪：`art_src/<皮肤键>_<动作>.png`（格式和素材包一样，一排 48×48）。
## **有它就直接用，不再跑 `strip_arms()`**——那个是按肤色连通块找胳膊的，只对 biker 好使：
## punk 那条胳膊裹着袖子、cyborg 那条整个是护甲，一个像素都匹配不上，原样留着就成了三条胳膊。
## 按各自调色板重跑也不行，那些颜色同时是躯干和腿的颜色，整个身子会被吃掉。
def own_body(name):
	path = os.path.join(OWN, "%s_%s.png" % (KEY, name))
	return path if os.path.exists(path) else None


def build_bodies(write):
	for name, (source, frames) in BODIES.items():
		mine = own_body(name)
		path = mine or os.path.join(SRC, "1 Characters", CHARACTER, source + ".png")
		_, _, pixels = read_png(path)
		right = []
		for index in frames:
			frame = cut(pixels, index * CELL, 0, CELL, CELL)
			if mine is None:
				frame = strip_arms(frame)
			right.append(place(frame, torso_center(frame), "%s 第%d帧" % (name, index + 1)))
		save_strip("body_%s_r.png" % name, right, write)
		save_strip("body_%s_l.png" % name, [mirror(f) for f in right], write)
		if mine is not None:
			print("    （用的是自己补的无臂版 art_src/%s）" % os.path.basename(mine))


# 爬梯子（2026-10 加的）：素材每个角色一组 `<名字>_climb.png`，6 帧、**背影**、两只手都在梯子上。
# 自带手臂（人是背对着的），所以不脱手臂、外观层爬梯时把单独贴的瞄准手臂藏起来。
# 背影没有「躯干那一列」好量，按每帧的外框居中；脚底照样落在帧底边。
CLIMB_FRAMES = [0, 1, 2, 3, 4, 5]


def build_climb(write):
	name = CHARACTER.split(" ", 1)[1]
	_, _, pixels = read_png(os.path.join(SRC, "1 Characters", CHARACTER, "%s_climb.png" % name))
	right = []
	for index in CLIMB_FRAMES:
		frame = cut(pixels, index * CELL, 0, CELL, CELL)
		xs = [x for row in frame for x, c in enumerate(row) if c[3] > 8]
		right.append(place(frame, (min(xs) + max(xs)) / 2.0, "climb 第%d帧" % (index + 1)))
	save_strip("body_climb_r.png", right, write)
	save_strip("body_climb_l.png", [mirror(f) for f in right], write)


def grip_in(gun, aim):
	"""转好向的枪身上，前握把落在图里的哪个位置（图自己的坐标）。"""
	length = math.hypot(aim[0], aim[1])
	axis = (aim[0] / length, aim[1] / length)
	perp = (-axis[1], axis[0])
	points = [(x, y) for y, row in enumerate(gun) for x, color in enumerate(row) if color[3] > 8]
	along = [x * axis[0] + y * axis[1] for x, y in points]
	across = [x * perp[0] + y * perp[1] for x, y in points]
	a = min(along) + GRIP_ALONG * (max(along) - min(along))
	c = (min(across) + max(across)) / 2.0 + GRIP_ACROSS
	return (axis[0] * a + perp[0] * c, axis[1] * a + perp[1] * c)


def build_arms(write):
	for look, gun_number in GUNS.items():
		print("  %s（%d 号枪）：" % (look, gun_number))
		build_arms_for(look, gun_number, write)


def build_arms_for(look, gun_number, write):
	hands = os.path.join(SRC, "3 Hands", CHARACTER)
	for name, (pose, variant, flip_v, degrees, hand, aim) in AIMS.items():
		frame = blank(CELL, CELL)
		_, _, back = read_png(os.path.join(hands, "%d.png" % pose))
		blit(frame, back, ARM_INSET_X, ARM_INSET_Y, "%s 的后手臂" % name)
		_, _, gun = read_png(os.path.join(SRC, "2 Guns", "%d_%s.png" % (gun_number, variant)))
		if flip_v:
			gun = gun[::-1]
		gun = rotate(gun, degrees)
		# 让枪的前握把正好落在那只手上
		grip = grip_in(gun, aim)
		blit(frame, gun, ARM_INSET_X + int(round(hand[0] - grip[0])), ARM_INSET_Y + int(round(hand[1] - grip[1])),
			"%s 的枪" % name)
		_, _, front = read_png(os.path.join(hands, "%d.png" % (pose + 5)))
		blit(frame, front, ARM_INSET_X, ARM_INSET_Y, "%s 的前手臂" % name)
		right = place(frame, ARM_BASELINE, "arms_%s_%s" % (look, name))
		save_strip("arms_%s_%s_r.png" % (look, name), [right], write)
		save_strip("arms_%s_%s_l.png" % (look, name), [mirror(right)], write)


## 握枪的手离胳膊最远能有多少像素。正下方那档枪夹在两条平行的胳膊中间、不压在任何一条上，
## 所以不能要求「正好落在胳膊上」；5px 足够松，又能抓住「数字写错、枪飘到别处」。
HAND_REACH = 5.0


def check_hands():
	"""量出来的手必须挨着某条胳膊，不然就是素材换了、数字没跟着改。"""
	hands = os.path.join(SRC, "3 Hands", CHARACTER)
	for name, entry in AIMS.items():
		pose, hand = entry[0], entry[4]
		best = 1e9
		for index in (pose, pose + 5):
			_, _, arm = read_png(os.path.join(hands, "%d.png" % index))
			for y, row in enumerate(arm):
				for x, color in enumerate(row):
					if color[3] > 8:
						best = min(best, math.hypot(x - hand[0], y - hand[1]))
		if best > HAND_REACH:
			_clipped.append("%s：握枪的手 (%g, %g) 离 %d.png / %d.png 都有 %.1fpx 远"
				% (name, hand[0], hand[1], pose, pose + 5, best))


## 人物选择界面上的头像：**直接用素材原本的待机第一帧**（角色自带胳膊、手里没枪）。
## 不能拿游戏里那张身体贴图——那是脱过胳膊的（见 `strip_arms`），头像上的人会空着两只袖子；
## 也不必把瞄准手臂贴回去，那会带出一根伸到框外的枪管，而选人的时候要看的是这个人长什么样。
PORTRAIT_SRC = "Idle1"
PORTRAIT_FRAME = 0
## 裁哪一块（源帧里的 x, y, 宽, 高）。三个角色四帧待机的并集是 x 2..22、y 13..47，各边留一点余量。
## **三个角色用同一个框**，界面上三张头像才对得齐、高矮才有可比性。
PORTRAIT_BOX = (2, 12, 22, 36)


def build_portrait(write):
	source = os.path.join(SRC, "1 Characters", CHARACTER, "%s.png" % PORTRAIT_SRC)
	_, height, art = read_png(source)
	left = PORTRAIT_FRAME * height + PORTRAIT_BOX[0]
	cut = blank(PORTRAIT_BOX[2], PORTRAIT_BOX[3])
	for y in range(PORTRAIT_BOX[3]):
		for x in range(PORTRAIT_BOX[2]):
			cut[y][x] = art[PORTRAIT_BOX[1] + y][left + x]
	if write:
		write_png(os.path.join(OUT, "portrait.png"), cut)
	print("  portrait.png  %d×%d（%s 第 %d 帧）" % (PORTRAIT_BOX[2], PORTRAIT_BOX[3],
		PORTRAIT_SRC, PORTRAIT_FRAME + 1))


def save_strip(name, frames, write):
	strip = blank(FRAME * len(frames), FRAME)
	for index, frame in enumerate(frames):
		blit(strip, frame, index * FRAME, 0, name)
	if write:
		write_png(os.path.join(OUT, name), strip)
	print("  %s  %d 帧" % (name, len(frames)))


## 切到某个角色：素材从哪个文件夹读、贴图写到哪、死亡动画用哪张。
def use_character(key):
	global CHARACTER, KEY, OUT, DEATH, PRONE, PRONE_TORSO, PRONE_TOLERANCE, PRONE_TORSO_X
	CHARACTER = CHARACTERS[key]
	KEY = key
	OUT = os.path.join(SKIN, key)
	# 死亡动画在角色自己的文件夹里，文件名是角色名去掉前面的编号：`1 Biker` → `Biker_death.png`
	DEATH = os.path.join(SRC, "1 Characters", CHARACTER, "%s_death.png" % CHARACTER.split(" ", 1)[1])
	PRONE, PRONE_TORSO, PRONE_TOLERANCE, PRONE_TORSO_X = PRONE_ART.get(key, PRONE_ART["biker"])
	if not os.path.isdir(OUT):
		os.makedirs(OUT)


def build_character(key, write):
	use_character(key)
	print("== %s（%s）==" % (key, CHARACTER))
	print("身体（脱掉素材自带的手臂）：")
	build_bodies(write)
	build_climb(write)
	print("死亡（角色自己那张 %s）：" % os.path.basename(DEATH))
	build_death(write)
	print("趴姿和爬行（自己画的 art_src/%s，原生分辨率，颜色贴回这个角色的调色板）：" % PRONE)
	build_prone(write)
	print("手臂 + 枪：")
	check_hands()
	build_arms(write)
	print("人物选择界面上的头像（素材原本的待机，自带胳膊、没有枪）：")
	build_portrait(write)


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(SRC):
		sys.exit("找不到原始素材包 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(SRC))
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	for key in (only if only else CHARACTERS):
		if key not in CHARACTERS:
			sys.exit("没有这个角色：%s（有的是 %s）" % (key, ", ".join(CHARACTERS)))
		build_character(key, write)
	if _clipped:
		print("\n有内容被画布切掉了：")
		for line in _clipped[:20]:
			print("  " + line)
		sys.exit(1)
	print("\n没有内容被切掉。" + ("" if write else "（--check：没有写文件）"))


if __name__ == "__main__":
	main()
