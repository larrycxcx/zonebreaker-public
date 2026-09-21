"""从敌人素材包生成赛博朋克皮肤包的敌人贴图，输出到 skins/cyberpunk/enemies/<敌人>/。

    python tools/enemy_build.py            # 全部重新生成
    python tools/enemy_build.py --check    # 只检查有没有内容被画布切掉，不写文件

素材来源是 CraftPix 的一个敌人包，解压在 art_in/default/enemies/（不进仓库，授权禁止再分发源文件）。
格式和玩家素材一样：每帧 48×48、脚底在帧底边。PNG 读写、镜像、锚点都复用 skin_build.py 那一套，
所以敌人和玩家站在同一条地面线上：锚点纵向同样让脚底落在身体原点下方 16px。
**帧比玩家宽**：80×56，锚点 (40, 40)——敌人倒地时整个人扑在身前，56 宽装不下，
左右各留 40px 才够（`EnemySpriteAppearance` 里的 FRAME_W / FRAME_H / ANCHOR 要和这里一致）。

和玩家不同的两点：
1. **敌人是一整张图**（枪画在身上），不用拼手臂，所以**不逐帧按躯干对齐**：
   整个角色只按待机第一帧的躯干定一次位，其余每一帧保留画师原本的摆位（走路的起伏、倒地的位移都在里面）。
2. **同一个素材出好几种敌人**：巡逻兵 A/B/C 都是 2 号，靠给衣服换色区分（`VARIANTS`）。
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "enemies")
OWN = os.path.join(HERE, "..", "art_src")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "enemies")

CELL = sb.CELL
FRAME_W, FRAME_H = 80, 56
ANCHOR = (40, 40)

# 巡逻兵（2 号，持枪朋克）：动作名 → (文件, 取哪几帧)。
# 素材的攻击动画是三组各 3 帧：水平、斜下、斜上——正好对上巡逻兵的瞄准方向。
# 趴下射击素材包里没有，是自己画的（art_src/walker_prone.png，一排 4 帧，第 1 帧不动、第 2 帧带枪口火光）。
WALKER_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
	"attack_level": ("Attack.png", [0, 1, 2]),
	"attack_down": ("Attack.png", [3, 4, 5]),
	"attack_up": ("Attack.png", [6, 7, 8]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
WALKER_PRONE = "walker_prone.png"
# 趴下那组按**上衣中心**另外定位，放在原点前方 5px（和玩家趴姿同一个规则）：
# 自己画的时候是在原来 48 宽的格子里往前躺的，照搬的话一趴下人会往前跳十几像素，
# 而趴下的判定框还是以原点为中心。四帧共用第一帧量出来的位置，开火那帧的相对动作保留。
PRONE_TORSO_X = 5

# 同一套素材换色出三种巡逻兵：原图的衣服颜色 → 新颜色（没列的颜色不动）。
# A 保持原样的紫；B 橙；C 红——C 射程最远、还会趴下，用最醒目的颜色。
# 不用绿色：F 的素材（1 号）本身就是绿衣服。
SHIRT = [(0x66, 0x3b, 0x93), (0x8b, 0x72, 0xde)]
VARIANTS = {
	"walker_a": {},
	"walker_b": {SHIRT[0]: (0xa8, 0x4a, 0x12), SHIRT[1]: (0xf0, 0x8c, 0x2c)},
	"walker_c": {SHIRT[0]: (0x8e, 0x16, 0x2a), SHIRT[1]: (0xd8, 0x3c, 0x4c)},
}


def palette_of(folder):
	"""素材自己的调色板：自己画的帧要贴回这套颜色（有损压缩会带进一堆近似色）。"""
	seen = {}
	for name in os.listdir(folder):
		if not name.lower().endswith(".png"):
			continue
		_, _, pixels = sb.read_png(os.path.join(folder, name))
		for row in pixels:
			for c in row:
				if c[3] > 8:
					seen[c[:3]] = seen.get(c[:3], 0) + 1
	return sorted(seen, key=lambda c: -seen[c])


def snap(pixels, colors):
	return [[(0, 0, 0, 0) if c[3] <= 8 else
		min(colors, key=lambda p: sum((p[i] - c[i]) ** 2 for i in range(3))) + (255,) for c in row] for row in pixels]


def recolor(frame, mapping):
	if not mapping:
		return frame
	return [[mapping[c[:3]] + (c[3],) if c[3] > 8 and c[:3] in mapping else c for c in row] for row in frame]


def frames_of(path, indices):
	_, _, pixels = sb.read_png(path)
	return [sb.cut(pixels, i * CELL, 0, CELL, CELL) for i in indices]


def own_frames(path, colors):
	"""自己画的那排：一格 48 宽、画布可能比 48 高；按最低那一行对齐到帧底边（和素材的脚底同一条线）。"""
	_, _, pixels = sb.read_png(path)
	pixels = snap(pixels, colors)
	height, width = len(pixels), len(pixels[0])
	bottom = max(y for y, row in enumerate(pixels) if any(c[3] for c in row))
	frames = []
	for i in range(width // CELL):
		frame = sb.blank(CELL, CELL)
		for y in range(height):
			ty = y - bottom + CELL - 1
			if 0 <= ty < CELL:
				frame[ty] = pixels[y][i * CELL:(i + 1) * CELL]
		frames.append(frame)
	return frames


def place(content, anchor_x, where):
	"""把 48×48 的一帧放进 80×56：anchor_x 那一列对准锚点，脚底（帧底边）落在原点下方 16px。"""
	out = sb.blank(FRAME_W, FRAME_H)
	sb.blit(out, content, ANCHOR[0] - int(round(anchor_x)), ANCHOR[1] + 16 - CELL, where)
	return out


def mirror(frame):
	"""按锚点那一列左右镜像，锚点自己不动（和玩家同一个做法）。"""
	out = sb.blank(FRAME_W, FRAME_H)
	for y, row in enumerate(frame):
		for x, c in enumerate(row):
			sx = 2 * ANCHOR[0] - x
			if c[3] > 8 and 0 <= sx < FRAME_W:
				out[y][sx] = c
	return out


def save(folder, name, frames, write):
	strip = sb.blank(FRAME_W * len(frames), FRAME_H)
	for index, frame in enumerate(frames):
		sb.blit(strip, frame, index * FRAME_W, 0, "%s/%s" % (folder, name))
	if write:
		sb.write_png(os.path.join(OUT, folder, name), strip)
	print("  %s/%s  %d 帧" % (folder, name, len(frames)))


def build_walkers(write):
	folder = os.path.join(PACK, "2")
	colors = palette_of(folder)
	clips = {name: frames_of(os.path.join(folder, f), idx) for name, (f, idx) in WALKER_CLIPS.items()}
	clips["prone"] = own_frames(os.path.join(OWN, WALKER_PRONE), colors)
	# 整个角色只定一次位：按待机第一帧的躯干中心；趴下那组另按上衣中心定位（见 PRONE_TORSO_X）
	anchor_x = sb.torso_center(clips["idle"][0])
	shirt = [x for row in clips["prone"][0] for x, c in enumerate(row) if c[3] > 8 and c[:3] in SHIRT]
	prone_anchor_x = sum(shirt) / len(shirt) - PRONE_TORSO_X
	for variant, mapping in VARIANTS.items():
		for name, frames in clips.items():
			ax = prone_anchor_x if name == "prone" else anchor_x
			right = [place(recolor(f, mapping), ax, "%s %s" % (variant, name)) for f in frames]
			save(variant, "%s_r.png" % name, right, write)
			save(variant, "%s_l.png" % name, [mirror(f) for f in right], write)


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(PACK):
		sys.exit("找不到敌人素材包 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(PACK))
	print("巡逻兵 A/B/C（2 号）：")
	build_walkers(write)
	if sb._clipped:
		print("\n有内容被画布切掉了：")
		for line in sb._clipped[:20]:
			print("  " + line)
		sys.exit(1)
	print("\n没有内容被切掉。" + ("" if write else "（--check：没有写文件）"))


if __name__ == "__main__":
	main()
