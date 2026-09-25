"""从敌人素材包生成赛博朋克皮肤包的敌人贴图，输出到 skins/cyberpunk/enemies/<敌人>/。

    python tools/enemy_build.py            # 全部重新生成
    python tools/enemy_build.py --check    # 只检查有没有内容被画布切掉，不写文件

素材来源是 CraftPix 的一个敌人包，解压在 art_in/default/enemies/（不进仓库，授权禁止再分发源文件）。
格式和玩家素材一样：每帧 48×48、脚底在帧底边。PNG 读写、镜像、锚点都复用 skin_build.py 那一套，
所以敌人和玩家站在同一条地面线上：锚点纵向同样让脚底落在身体原点下方 16px。
**帧比玩家宽**：80×56，锚点 (40, 40)——敌人倒地时整个人扑在身前，56 宽装不下，
左右各留 40px 才够（`EnemySpriteAppearance` 里的 FRAME_W / FRAME_H / ANCHOR 要和这里一致）。

和玩家不同的几点：
1. **敌人是一整张图**（枪画在身上），不用拼手臂，所以**不逐帧按躯干对齐**：
   整个角色只按待机第一帧的躯干定一次位，其余每一帧保留画师原本的摆位（走路的起伏、倒地的位移都在里面）。
2. **同一个素材出好几种敌人**：巡逻兵 A/B/C 都是 2 号，靠给衣服换色区分（`VARIANTS`）。
3. **飞行的 E（5 号无人机）不站在地上**：它的判定框（28×20）以原点为中心，所以锚点对的是**机身中心**，
   不是脚底；帧也用素材原本的 48×48（锚点 24, 24），放得下攻击时往下劈的闪电和坠毁时往下掉的那一段。
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
	"1_a": {},
	"1_b": {SHIRT[0]: (0xa8, 0x4a, 0x12), SHIRT[1]: (0xf0, 0x8c, 0x2c)},
	"1_c": {SHIRT[0]: (0x8e, 0x16, 0x2a), SHIRT[1]: (0xd8, 0x3c, 0x4c)},
}


# 敌人 D（3 号滑板手）和 F（1 号球棒手）：一个素材出一种敌人，动作直接对上，整个角色按一帧的躯干定一次位。
# 键是输出的动作名（EnemySpriteAppearance 按它挑），值是 (文件, 取哪几帧)；ANCHOR_CLIP 是拿哪个动作的第 1 帧定位。
# D：平时踩着滑板溜（walk）；冲锋时站在板上冲（run，素材的 Attack）；跳起来也用板上那组第 1 帧（air）；
#    素材有两组受伤，用踩在板上的 Hurt2——D 几乎总在板上。Idle 是提着滑板站着，只有被卡住不动时才看得到。
# F：扔手雷 = 用球棒把手雷打出去。素材 Attack 前 3 帧是准备（和待机几乎一样），第 4 帧是挥棒的弧光，
#    所以开火动作从第 4 帧开始：手雷飞出去的那一刻画面上正好是球棒打中，扔的时机不用改。
SINGLES = {
	"1_d": ("3", "walk", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Attack.png", [0, 1, 2, 3]),
		"air": ("Attack.png", [0]),
		"hurt": ("Hurt2.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	"1_f": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}


# Boss A：boss 包的 2 号，四条腿的导弹机甲（art_in/default/boss/2/，CraftPix，不进仓库）。每帧 72×72，**不缩放**：
# 判定框按它改成 56×48（原来 48×64 的瘦高个），脚底在原点下方 24px。输出帧 96×80、锚点 (48, 56)，
# 放得下喷射跳跃时往上抬的那一截。横向按机身和腿（BOSS_BODY_ROWS 那几行）居中——背上的导弹巢偏后，按它量会偏。
# 站着开火是 Attack1（导弹巢连发），边走边开火是 Attack2，空中用 Attack4（腿上喷火往上跳）里身体抬起来的两帧。
# Attack3（车头贴地光束）和 Sneer（嘲讽）暂时没用上。
BOSS_DIR = os.path.join(HERE, "..", "art_in", "default", "boss", "2")
BOSS_CELL = 72
BOSS_FRAME_W, BOSS_FRAME_H = 96, 80
BOSS_ANCHOR = (48, 56)
BOSS_FOOT = 24
BOSS_BODY_ROWS = (40, 72)
BOSS_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
	"attack_level": ("Attack1.png", [0, 1, 2, 3, 4, 5, 6, 7]),
	"attack_walk": ("Attack2.png", [0, 1, 2, 3, 4, 5]),
	"air": ("Attack4.png", [2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
# HUD 头像：从待机第一帧截导弹巢和车头那一块（32×32，HUD 上 1:1 显示）。
BOSS_PORTRAIT = (20, 20, 32, 32)


# 炮台（6 号，履带炮塔）。素材只有水平炮管；斜上 / 斜下是在 Idle.png 上手改炮管画的
# （art_in/extra/turret_diag_*.png，含素材包的像素，所以和素材包一样不进仓库），生成时移植到攻击、受伤帧上。
# Walk 就是履带在滚，炮台不走，不用。
TURRET_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_level": ("Attack.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3]),
}
TURRET_DIAG = {"up": "turret_diag_up.png", "down": "turret_diag_down.png"}
EXTRA = os.path.join(HERE, "..", "art_in", "extra")
TURRET_BODY_RIGHT = 25        # 机身右边缘（再往右是炮管）；手改只许动这一列往左 2px 以右
TURRET_BARREL_ROWS = (26, 33)  # 原来水平炮管那几行：斜炮管的颜色贴回这里出现过的那几种
TURRET_MOUNT_ROWS = (26, 38)   # 炮管装在这一截上：后坐时它整体平移（圆顶挪得更多，是挤压），斜炮管跟着它走
TURRET_MOUNT_SLACK = 16        # 上面那一截允许差几个像素（后坐时的挤压）
TURRET_COLUMN_ROWS = (21, 25)  # 圆顶下面的立柱，横向按它居中
TURRET_OUTLINE_AT = (14, 14)   # 圆顶最上面一个描边像素，取描边色


# 敌人 E（5 号无人机）。Idle 和 Walk 两组画得一模一样（悬停时螺旋桨转），只取 Idle；
# Attack 是往正下方放电，正好是 E 竖直向下开火。
FLYER_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_down": ("Attack.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3]),
}
FLYER_FRAME = 48
FLYER_ANCHOR = (24, 24)


# ---------------------------------------------------------------- 工业区（第二关）
# 素材 CraftPix Industrial Zone Enemies（不进仓库）。格式和赛博朋克那套一样（48×48、脚底在帧底边），
# 所以五个走地上的直接走 `build_singles`、会飞的走 `build_flyer`，一行新代码都不用写。
# 值是 (素材目录, 拿哪个动作的第 1 帧定位, {输出动作名: (文件, 取哪几帧)})。
#
# 这套素材**没有斜射姿势**（赛博朋克那个巡逻兵自带水平 / 斜上 / 斜下三组，这套只有水平一组），
# 所以 2-C 斜着打时画面上还是水平端枪的样子。要做准就得像炮台那样手改几帧放进 `art_in/extra/`。
IND_PACK = os.path.join(HERE, "..", "art_in", "default", "industrial-zone-tileset", "industrial-zone-enemies")
IND_OUT = os.path.join(HERE, "..", "skins", "industrial", "enemies")
IND_SINGLES = {
	# 2-A Worker：从天而降，落地后冲向玩家（复用 D 那套追击）。跑和冲用同一组。
	"2_a": ("1 Worker", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Run.png", [2]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 2-B Heaver：光膀子的壮汉，也是冲撞。Attack 是双手举过头顶砸下来，当冲撞时的姿势。
	"2_b": ("3 Heaver", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Run.png", [2]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 2-C Specialist：巡逻 + 射击。Attack 8 帧是一整轮连发（1~2 帧枪口火光、5~8 帧退壳），
	# 单发只取前 3 帧，和赛博朋克巡逻兵一组的长度一致。
	"2_c": ("2 Specialist", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 2-D Hammer：履带机器人，走近了抡锤砸。Attack 8 帧是完整一抡——抬起、蓄力、砸下，
	# **第 6 帧锤头正砸在身前地上**，伤害判定要卡在那一帧（见 enemy_hammer.gd 的 HIT_FRAME）。
	"2_d": ("6 Hammer", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Run.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5, 6, 7]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3]),
	}),
	# 2-F Alarmobot：小履带机器人，发现玩家就拉警报冲过来贴身自爆。
	# Alarm 那组（红色声波）就是「拉响了、要炸了」的样子；Death 本身就是爆炸。
	"2_f": ("4 Alarmobot", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3, 4, 5]),
		"walk": ("Run.png", [0, 1, 2, 3]),
		"run": ("Run.png", [0, 1, 2, 3]),
		"attack_level": ("Alarm.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}
# 2-E Copter：直升机无人机，飞在头顶往下扔炸弹（复用 E 的飞行 + 现成的手雷）。
# Attack 6 帧里**第 3 帧炸弹脱钩**，所以手雷在那一帧出手（见 enemy_copter.gd）。
# 机身是哪几行（桅杆和桨叶以下）：这架的机身底边和桨叶一样宽，自动判据认不出来。
IND_FLYER_BODY = (20, 34)
IND_FLYER = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_down": ("Attack.png", [0, 1, 2, 3, 4, 5]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
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
	return mirror_about(frame, ANCHOR[0])


def save(folder, name, frames, write, out=None):
	save_frames(folder, name, frames, FRAME_W, FRAME_H, write, out)


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


def build_singles(write, singles=None, pack=None, out=None):
	"""一个素材出一种敌人：动作直接对上，整个角色按一帧的躯干定一次位。"""
	for name, (number, anchor_clip, table) in (singles if singles else SINGLES).items():
		folder = os.path.join(pack if pack else PACK, number)
		clips = {clip: frames_of(os.path.join(folder, f), idx) for clip, (f, idx) in table.items()}
		anchor_x = sb.torso_center(clips[anchor_clip][0])
		for clip, frames in clips.items():
			right = [place(f, anchor_x, "%s %s" % (name, clip)) for f in frames]
			save(name, "%s_r.png" % clip, right, write, out)
			save(name, "%s_l.png" % clip, [mirror(f) for f in right], write, out)


def build_boss(write):
	clips = {}
	for name, (f, idx) in BOSS_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(BOSS_DIR, f))
		clips[name] = [sb.cut(pixels, i * BOSS_CELL, 0, BOSS_CELL, BOSS_CELL) for i in idx]
	first = clips["idle"][0]
	body = [x for y in range(*BOSS_BODY_ROWS) for x, c in enumerate(first[y]) if c[3] > 8]
	anchor_x = (min(body) + max(body)) / 2.0
	dx = BOSS_ANCHOR[0] - int(round(anchor_x))
	dy = BOSS_ANCHOR[1] + BOSS_FOOT - BOSS_CELL
	for name, frames in clips.items():
		right = []
		for f in frames:
			out = sb.blank(BOSS_FRAME_W, BOSS_FRAME_H)
			sb.blit(out, f, dx, dy, "1_boss %s" % name)
			right.append(out)
		save_frames("1_boss", "%s_r.png" % name, right, BOSS_FRAME_W, BOSS_FRAME_H, write)
		save_frames("1_boss", "%s_l.png" % name, [mirror_about(f, BOSS_ANCHOR[0]) for f in right],
			BOSS_FRAME_W, BOSS_FRAME_H, write)
	x, y, w, h = BOSS_PORTRAIT
	if write:
		sb.write_png(os.path.join(OUT, "1_boss", "portrait.png"), sb.cut(first, x, y, w, h))
	print("  1_boss/portrait.png  %dx%d" % (w, h))


def build_turret(write):
	"""炮台：水平那几组直接用素材；斜上 / 斜下是把手改的炮管移植到每一帧上（见 TURRET_DIAG）。"""
	folder = os.path.join(PACK, "6")
	clips = {name: frames_of(os.path.join(folder, f), idx) for name, (f, idx) in TURRET_CLIPS.items()}
	idle = clips["idle"]
	outline = idle[0][TURRET_OUTLINE_AT[1]][TURRET_OUTLINE_AT[0]]
	for aim, source in TURRET_DIAG.items():
		drawn = diag_sheet(os.path.join(EXTRA, source), idle)
		# 攻击帧：炮台后坐时装炮管那一截往后上方平移，斜炮管跟着同样平移
		clips["attack_" + aim] = [graft(f, drawn[0], mount_offset(f, idle[0])) for f in clips["attack_level"]]
		clips["idle_" + aim] = [d["frame"] for d in drawn]
		# 受伤：第 1 帧和待机一样；第 2 帧整个炮台闪成一片黄，新炮管也要涂成同一种闪光色
		hurt = clips["hurt"]
		flash_color = most_common(hurt[1], skip=[outline])
		clips["hurt_" + aim] = [graft(hurt[0], drawn[0], (0, 0)), flashed(hurt[1], drawn[1], outline, flash_color)]
	# 横向按炮塔立柱（圆顶下面那一截）居中，炮管、履带都不算
	column = [x for y in range(*TURRET_COLUMN_ROWS) for x, c in enumerate(idle[0][y]) if c[3] > 8]
	anchor_x = (min(column) + max(column)) / 2.0
	for name, frames in clips.items():
		right = [place(f, anchor_x, "turret %s" % name) for f in frames]
		save("1_g", "%s_r.png" % name, right, write)
		save("1_g", "%s_l.png" % name, [mirror(f) for f in right], write)


def diag_sheet(path, idle):
	"""读一张手改的斜炮管图（在 Idle.png 上只改炮管那一块）：返回每一帧的「改了哪些像素」和清理后的整帧。
	改动必须只在炮管那一侧，机身一个像素都不能动——否则没法移植到攻击 / 受伤帧上，直接报错。"""
	width, height, pixels = sb.read_png(path)
	assert width == CELL * len(idle), "%s 应该和 Idle.png 一样宽（%d），实际 %d" % (path, CELL * len(idle), width)
	assert not any(c[3] > 8 for row in pixels[CELL:] for c in row), "%s 在第 %d 行以下还有内容" % (path, CELL)
	barrel_colors = sorted({c[:3] for y in range(*TURRET_BARREL_ROWS) for c in idle[0][y][TURRET_BODY_RIGHT:] if c[3] > 8})
	out = []
	for i, original in enumerate(idle):
		frame = sb.cut(pixels, i * CELL, 0, CELL, CELL)
		changed = [(x, y) for y in range(CELL) for x in range(CELL)
			if visible(frame[y][x]) != visible(original[y][x])
			or (visible(frame[y][x]) and frame[y][x][:3] != original[y][x][:3])]
		stray = [(x, y) for x, y in changed if x < TURRET_BODY_RIGHT - 2]
		assert not stray, "%s 第 %d 帧改动了机身：%s" % (path, i + 1, stray[:5])
		clean = [row[:] for row in original]
		for x, y in changed:
			c = frame[y][x]
			# 编辑器旋转时抗锯齿出来的半透明边和近似色：透明度二值化，颜色贴回炮管原来那几种
			clean[y][x] = (0, 0, 0, 0) if c[3] < 128 else \
				min(barrel_colors, key=lambda p: sum((p[k] - c[k]) ** 2 for k in range(3))) + (255,)
		out.append({"changed": changed, "frame": clean})
	return out


def visible(c):
	return c[3] >= 128


def mount_offset(frame, idle):
	"""这一帧装炮管的那一截（炮管以左）相对待机第一帧挪了多少。"""
	best = None
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			miss = 0
			for y in range(*TURRET_MOUNT_ROWS):
				for x in range(TURRET_BODY_RIGHT):
					sx, sy = x + dx, y + dy
					a = frame[sy][sx] if 0 <= sx < CELL and 0 <= sy < CELL else (0, 0, 0, 0)
					b = idle[y][x]
					if (a[3] > 8) != (b[3] > 8) or (a[3] > 8 and a[:3] != b[:3]):
						miss += 1
			if best is None or miss < best[0]:
				best = (miss, dx, dy)
	# 后坐那帧除了平移还有一点挤压（顶边、炮管根部），允许边上差几个像素；差多了说明素材换了、这套移植不适用
	assert best[0] <= TURRET_MOUNT_SLACK, "装炮管那一截对不上待机帧（差 %d 个像素），不是单纯平移" % best[0]
	return best[1], best[2]


def graft(frame, drawn, offset):
	"""把手改的那一块（擦掉的水平炮管 + 新画的斜炮管）按 offset 平移后贴到这一帧上。"""
	out = [row[:] for row in frame]
	for x, y in drawn["changed"]:
		tx, ty = x + offset[0], y + offset[1]
		if 0 <= tx < CELL and 0 <= ty < CELL:
			out[ty][tx] = drawn["frame"][y][x]
	return out


def flashed(flash, drawn, outline, flash_color):
	"""闪光帧：改动的那一块里，外轮廓保持黑色，其余涂成闪光色。"""
	out = [row[:] for row in flash]
	frame = drawn["frame"]
	for x, y in drawn["changed"]:
		c = frame[y][x]
		if c[3] <= 8:
			out[y][x] = (0, 0, 0, 0)
			continue
		edge = any(not (0 <= x + dx < CELL and 0 <= y + dy < CELL) or frame[y + dy][x + dx][3] <= 8
			for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)])
		out[y][x] = outline if edge and c[:3] == outline[:3] else flash_color
	return out


def most_common(frame, skip):
	count = {}
	for row in frame:
		for c in row:
			if c[3] > 8 and c not in skip:
				count[c] = count.get(c, 0) + 1
	return max(count, key=count.get)


def build_flyer(write, key="1_e", number="5", table=None, pack=None, out_root=None, body_rows=None):
	"""会飞的那个：整组按待机第一帧的机身（螺旋桨以下）定一次位，机身中心对准锚点。"""
	folder = os.path.join(pack if pack else PACK, number)
	clips = {name: frames_of(os.path.join(folder, f), idx)
		for name, (f, idx) in (table if table else FLYER_CLIPS).items()}
	first = clips["idle"][0]
	# 机身 = 螺旋桨下面那一截：从最宽的那几行（螺旋桨）往下数，跳过桅杆。
	rows = [y for y, row in enumerate(first) if any(c[3] > 8 for c in row)]
	widths = {y: sum(1 for c in first[y] if c[3] > 8) for y in rows}
	if body_rows is None:
		rotor_bottom = max(y for y in rows if widths[y] == max(widths.values()))
		body = [(x, y) for y in rows if y > rotor_bottom and widths[y] > 6
			for x, c in enumerate(first[y]) if c[3] > 8]
	else:
		# **机身和桨叶一样宽的画法，上面那句认不出来**（工业区那架直升机机身底边和桨叶都是 17 宽，
		# 「最宽的最后一行」直接取到机身底边、下面一行都不剩）。这种就直接把机身是哪几行写出来。
		# 不改上面那句的判据：绿区那架已经对好了，为了新素材去动它会把整张图挪掉 1px。
		body = [(x, y) for y in range(body_rows[0], body_rows[1]) if y in widths
			for x, c in enumerate(first[y]) if c[3] > 8]
	xs = [x for x, _ in body]
	top = min(y for y in rows)
	bottom = max(y for y in rows)
	# 横向：机身中心；纵向：整个飞行器（含螺旋桨）的中心——判定框 28×20 就是把螺旋桨算在里面的
	dx = FLYER_ANCHOR[0] - int(round((min(xs) + max(xs)) / 2.0))
	dy = FLYER_ANCHOR[1] - int(round((top + bottom) / 2.0))
	for name, frames in clips.items():
		right = []
		for f in frames:
			# 注意这里不能叫 out：会盖掉参数里那个输出目录
			placed = sb.blank(FLYER_FRAME, FLYER_FRAME)
			sb.blit(placed, f, dx, dy, "flyer %s" % name)
			right.append(placed)
		left = [mirror_about(f, FLYER_ANCHOR[0]) for f in right]
		save_frames(key, "%s_r.png" % name, right, FLYER_FRAME, FLYER_FRAME, write, out_root)
		save_frames(key, "%s_l.png" % name, left, FLYER_FRAME, FLYER_FRAME, write, out_root)


def mirror_about(frame, column):
	out = sb.blank(len(frame[0]), len(frame))
	for y, row in enumerate(frame):
		for x, c in enumerate(row):
			sx = 2 * column - x
			if c[3] > 8:
				if 0 <= sx < len(row):
					out[y][sx] = c
				else:
					sb._clipped.append("镜像后出界：(%d, %d)" % (x, y))
	return out


def save_frames(folder, name, frames, width, height, write, out=None):
	strip = sb.blank(width * len(frames), height)
	for index, frame in enumerate(frames):
		sb.blit(strip, frame, index * width, 0, "%s/%s" % (folder, name))
	if write:
		sb.write_png(os.path.join(out if out else OUT, folder, name), strip)
	print("  %s/%s  %d 帧" % (folder, name, len(frames)))


def build_industrial(write):
	if not os.path.isdir(IND_PACK):
		sys.exit("找不到工业区敌人素材 %s（不在仓库里，要自己解压进去）" % os.path.normpath(IND_PACK))
	build_singles(write, IND_SINGLES, IND_PACK, IND_OUT)
	build_flyer(write, "2_e", "5 Copter", IND_FLYER, IND_PACK, IND_OUT, IND_FLYER_BODY)


def main():
	write = "--check" not in sys.argv
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	if only == ["industrial"]:
		print("工业区（第二关）的六种敌人：")
		build_industrial(write)
		_report(write)
		return
	if not os.path.isdir(PACK):
		sys.exit("找不到敌人素材包 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(PACK))
	print("巡逻兵 A/B/C（2 号）：")
	build_walkers(write)
	print("D（3 号）和 F（1 号）：")
	build_singles(write)
	print("Boss A（boss 包 2 号）：")
	build_boss(write)
	print("炮台（6 号）：")
	build_turret(write)
	print("飞行的 E（5 号）：")
	build_flyer(write)
	print("工业区（第二关）的六种敌人：")
	build_industrial(write)
	_report(write)


def _report(write):
	if sb._clipped:
		print("\n有内容被画布切掉了：")
		for line in sb._clipped[:20]:
			print("  " + line)
		sys.exit(1)
	print("\n没有内容被切掉。" + ("" if write else "（--check：没有写文件）"))


if __name__ == "__main__":
	main()
