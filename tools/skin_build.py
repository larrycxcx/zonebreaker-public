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
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "player")

CHARACTER = "1 Biker"
# 用哪把枪当步枪的外观（`2 Guns/` 里的编号，1 是最像突击步枪的那把）。
GUN = 1

CELL = 48          # 素材每帧的边长
ARM_CELL = 32      # 手臂/枪格子的边长，居中放在角色帧里
ARM_INSET = (CELL - ARM_CELL) // 2
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
	"crouch": ("Sitdown1", [2]),
}

# 瞄准方向 → (手臂编号, 用哪张枪, 是否上下翻转, 旋转角度, 握枪那只手在 32×32 格子里的位置, 子弹飞的方向)。
# 手臂 1~5 是后手臂（画在枪后面），6~10 是同样 5 个方向的前手臂（画在枪前面）。
# 枪只有水平（`_1`）和斜下 45°（`_2`）两张：斜上是把斜下那张上下翻过来，正上/正下是把水平那张转 90°。
#
# **枪放在哪里由「手在哪里」决定，不要自己推**：素材里手臂不是绕一个固定点转的，
# 画师每个方向都把整条胳膊挪了位置，按「握把固定在格子中心」推出来的落点五个方向里错四个。
# 手的位置是从 Hands.psd 量的：前手臂那组里的 `Deep_shadows` 图层就是从枪另一侧露出来的那只手。
# **正下方那张是例外**：它没有这块小方块，因为前面那条胳膊只是垂着、根本没握枪——
# 握枪的是后面那条（`1.png`，在身体右侧），所以这一档量的是后手臂的下端。
AIMS = {
	"down":      (1, "1", False,  90, (16.5, 25.0), (0, 1)),
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
		blit(frame, back, ARM_INSET, ARM_INSET, "%s 的后手臂" % name)
		_, _, gun = read_png(os.path.join(SRC, "2 Guns", "%d_%s.png" % (GUN, variant)))
		if flip_v:
			gun = gun[::-1]
		gun = rotate(gun, degrees)
		# 让枪的前握把正好落在那只手上
		grip = grip_in(gun, aim)
		blit(frame, gun, ARM_INSET + int(round(hand[0] - grip[0])), ARM_INSET + int(round(hand[1] - grip[1])),
			"%s 的枪" % name)
		_, _, front = read_png(os.path.join(hands, "%d.png" % (pose + 5)))
		blit(frame, front, ARM_INSET, ARM_INSET, "%s 的前手臂" % name)
		right = place(frame, ARM_BASELINE, "arms_%s" % name)
		save_strip("arms_%s_r.png" % name, [right], write)
		save_strip("arms_%s_l.png" % name, [mirror(right)], write)


def check_hands():
	"""量出来的手必须真的落在某条胳膊上，不然就是素材换了、数字没跟着改。"""
	hands = os.path.join(SRC, "3 Hands", CHARACTER)
	for name, entry in AIMS.items():
		pose, hand = entry[0], entry[4]
		x, y = int(round(hand[0])), int(round(hand[1]))
		on = []
		for index in (pose, pose + 5):
			_, _, arm = read_png(os.path.join(hands, "%d.png" % index))
			if any(arm[y + dy][x + dx][3] > 8 for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
				on.append(index)
		if not on:
			_clipped.append("%s：握枪的手 (%g, %g) 不在 %d.png 和 %d.png 上"
				% (name, hand[0], hand[1], pose, pose + 5))


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
