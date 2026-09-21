"""从原始素材包生成赛博朋克皮肤包的玩家贴图，输出到 skins/cyberpunk/player/。

    python tools/skin_build.py            # 全部重新生成
    python tools/skin_build.py --check    # 只检查有没有内容被画布切掉，不写文件

素材来源是 CraftPix 那套「Free Guns for Cyberpunk Characters」，解压在 art_in/default/
（不进仓库，授权禁止再分发源文件）。这个脚本做三件事：

1. **挑无手臂的身体**：素材里 `Idle1` 是带手臂的完整角色，`Idle2` 把手臂去掉了，
   就是留给你贴瞄准手臂的。所以身体一律取 `*2.png`。
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
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "player")

CHARACTER = "1 Biker"
# 用哪把枪当步枪的外观（`2 Guns/` 里的编号）。
# **别挑太小的枪**：素材里的后手臂是按「大部分被枪挡住」画的，1 号枪只有 26×7，
# 斜射时那条粗胳膊会整根露在枪外面，看着像身上挂了根香肠。4 号 29×11，正好压得住。
GUN = 4

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
# air 只要两帧：上升用蜷腿那帧、下落用伸腿那帧，运行时按纵向速度选，不按时间播。
# crouch 取下蹲循环里压得最低的那一帧。
BODIES = {
	"idle": ("Idle2", [0, 1, 2, 3]),
	"walk": ("Walk2", [0, 1, 2, 3, 4, 5]),
	"run": ("Run2", [0, 1, 2, 3, 4, 5]),
	"air": ("Jump2", [1, 2]),
}

# 趴下和爬行**不在素材包里**（CraftPix 那套只有单膝跪姿），是自己画的，放在 art_src/（进仓库）。
# `biker_prone.png` 是**原生分辨率**的一排四帧（约 43×14 一帧，帧与帧之间隔着空列），1:1 使用、不缩放。
# 原图是按 9 倍放大、再存成有损 webp 交过来的，按 9px 的网格逐格取中间那点的众数还原回来的；
# 以后再补图，**直接导出 1 倍大小的 PNG**，就不用再做这一步。
# **高度是有规矩的**：每一帧都要藏在敌人站着开枪的子弹下面，又要和 12px 的判定框差不多高，
# test_cyberpunk_skin.gd 逐帧守着。
PRONE = "biker_prone.png"
PRONE_STILL = 1              # 趴着不动用第几帧（从 0 数）
PRONE_CRAWL = [0, 1, 2, 3]   # 爬行循环用哪几帧、什么顺序：腿伸直 → 收膝 → 再伸直
# 四帧按**上衣（躯干）中心**对齐：爬的时候前半身基本不动、腿往上收，按躯干对齐人才不会原地前后滑。
# 躯干放在身体原点前方 5px，这样静止那帧整体大致对着原点（头在前、脚在后，头短脚长）。
PRONE_TORSO_X = 5

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

def torso_center(frame):
	"""这一帧躯干（头 + 上半身）的横向中心。手臂就贴在这个位置上。"""
	left = right = None
	for y in range(TORSO_ROWS[0], TORSO_ROWS[1] + 1):
		for x, color in enumerate(frame[y]):
			if color[3] > 8:
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
	"""上衣（粉红那几种颜色）的横向中心。"""
	xs = [x for row in art for x, c in enumerate(row) if c[3] and c[0] > 160 and c[1] < 90]
	return sum(xs) / len(xs)


def place_prone(art, where):
	frame = blank(FRAME, FRAME)
	bottom = max(y for y, row in enumerate(art) if any(c[3] for c in row))
	# 躯干对准原点前方 PRONE_TORSO_X，最低那一行落在原点下方 16px（和站姿同一条地面线）
	blit(frame, art, ANCHOR[0] + PRONE_TORSO_X - int(round(torso_x(art))), ANCHOR[1] + 16 - 1 - bottom, where)
	return frame


def build_prone(write):
	colors = palette()
	frames = [restyle(f, colors) for f in prone_frames()]
	still = [place_prone(frames[PRONE_STILL], "crouch")]
	crawl = [place_prone(frames[i], "crawl 第%d帧" % (i + 1)) for i in PRONE_CRAWL]
	save_strip("body_crouch_r.png", still, write)
	save_strip("body_crouch_l.png", [mirror(f) for f in still], write)
	save_strip("body_crawl_r.png", crawl, write)
	save_strip("body_crawl_l.png", [mirror(f) for f in crawl], write)


def build_bodies(write):
	for name, (source, frames) in BODIES.items():
		path = os.path.join(SRC, "1 Characters", CHARACTER, source + ".png")
		_, _, pixels = read_png(path)
		right = []
		for index in frames:
			frame = cut(pixels, index * CELL, 0, CELL, CELL)
			right.append(place(frame, torso_center(frame), "%s 第%d帧" % (name, index + 1)))
		save_strip("body_%s_r.png" % name, right, write)
		save_strip("body_%s_l.png" % name, [mirror(f) for f in right], write)


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
	hands = os.path.join(SRC, "3 Hands", CHARACTER)
	for name, (pose, variant, flip_v, degrees, hand, aim) in AIMS.items():
		frame = blank(CELL, CELL)
		_, _, back = read_png(os.path.join(hands, "%d.png" % pose))
		blit(frame, back, ARM_INSET_X, ARM_INSET_Y, "%s 的后手臂" % name)
		_, _, gun = read_png(os.path.join(SRC, "2 Guns", "%d_%s.png" % (GUN, variant)))
		if flip_v:
			gun = gun[::-1]
		gun = rotate(gun, degrees)
		# 让枪的前握把正好落在那只手上
		grip = grip_in(gun, aim)
		blit(frame, gun, ARM_INSET_X + int(round(hand[0] - grip[0])), ARM_INSET_Y + int(round(hand[1] - grip[1])),
			"%s 的枪" % name)
		_, _, front = read_png(os.path.join(hands, "%d.png" % (pose + 5)))
		blit(frame, front, ARM_INSET_X, ARM_INSET_Y, "%s 的前手臂" % name)
		right = place(frame, ARM_BASELINE, "arms_%s" % name)
		save_strip("arms_%s_r.png" % name, [right], write)
		save_strip("arms_%s_l.png" % name, [mirror(right)], write)


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


def save_strip(name, frames, write):
	strip = blank(FRAME * len(frames), FRAME)
	for index, frame in enumerate(frames):
		blit(strip, frame, index * FRAME, 0, name)
	if write:
		write_png(os.path.join(OUT, name), strip)
	print("  %s  %d 帧" % (name, len(frames)))


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(SRC):
		sys.exit("找不到原始素材包 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(SRC))
	print("身体（%s，无手臂版）：" % CHARACTER)
	build_bodies(write)
	print("趴姿和爬行（自己画的 art_src/%s，原生分辨率）：" % PRONE)
	build_prone(write)
	print("手臂 + %d 号枪：" % GUN)
	check_hands()
	build_arms(write)
	if _clipped:
		print("\n有内容被画布切掉了：")
		for line in _clipped[:20]:
			print("  " + line)
		sys.exit(1)
	print("\n没有内容被切掉。" + ("" if write else "（--check：没有写文件）"))


if __name__ == "__main__":
	main()
