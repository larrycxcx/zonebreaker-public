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


## 整帧内容的横向中心。**不是人形的那些用它**（趴在地上的鲨鱼机、带轮子的炮车）：
## `sb.torso_center()` 量的是「头 + 上半身」那条带，矮趴趴的东西在那几行里一个像素都没有。
def box_center(frame):
	xs = [x for row in frame for x, c in enumerate(row) if c[3] > 8]
	return (min(xs) + max(xs)) / 2.0


def build_singles(write, singles=None, pack=None, out=None):
	"""一个素材出一种敌人：动作直接对上，整个角色按一帧定一次位。
	表里第四个值是「按什么定位」：`torso`（默认，人形）或 `box`（按整帧外框，矮趴趴的那些）。"""
	for name, entry in (singles if singles else SINGLES).items():
		number, anchor_clip, table = entry[0], entry[1], entry[2]
		how = entry[3] if len(entry) > 3 else "torso"
		folder = os.path.join(pack if pack else PACK, number)
		clips = {clip: frames_of(os.path.join(folder, f), idx) for clip, (f, idx) in table.items()}
		anchor_x = sb.torso_center(clips[anchor_clip][0]) if how == "torso" 			else box_center(clips[anchor_clip][0])
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


def build_flyer(write, key="1_e", number="5", table=None, pack=None, out_root=None, body_rows=None,
		faces_left=False):
	"""会飞的那个：整组按待机第一帧的机身（螺旋桨以下）定一次位，机身中心对准锚点。
	`faces_left`：素材是**朝左**画的（地下室那架无人机枪管在左边）。读进来先整帧翻过来，
	后面一律按朝右处理——输出的 `_r` 永远是朝右的，外观层才不用分情况。"""
	folder = os.path.join(pack if pack else PACK, number)
	clips = {name: frames_of(os.path.join(folder, f), idx)
		for name, (f, idx) in (table if table else FLYER_CLIPS).items()}
	if faces_left:
		clips = {name: [[list(reversed(row)) for row in f] for f in frames] for name, frames in clips.items()}
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


# ---------------------------------------------------------------- 工业区的 Boss（机械操作员）
# 素材是**两样东西**：一个在空中飘的铁球（Idle / Left / Right / Attack1-2 / Hurt / Death），
# 和一条吊在缆绳上的机械爪（Move / Up-Down / Attack3-4）。
# 我们把球当本体、爪当它伸下来的手臂——正好对上「铁球八方向飞、从上方伸下手臂打下面的玩家、
# 不伸手臂就打一串子弹」。
#
# 球每帧 96×96、本体约 90×90、**画在格子正中**，所以整组直接原样搬进去，锚点就是格子中心。
# 判定框 72×72：比画面小一圈，和 Boss A「保留素材尺寸、判定框略小」是同一条。
BOSS2_DIR = os.path.join(IND_PACK, "..", "industrial-zone-boss", "3 Machine operator")
BOSS2_OUT = "2_boss"
BOSS2_CELL = 96
BOSS2_ANCHOR = (48, 48)
BOSS2_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Right.png", [0, 1, 2, 3, 4, 5, 6, 7]),
	"attack_level": ("Attack2.png", [0, 1, 2, 3, 4, 5, 6, 7]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
# HUD 头像：球正中那 32×32，红环和头冠都在里面。
BOSS2_PORTRAIT = (32, 32, 32, 32)
# 手臂**不按帧用**：素材里那 6 帧只有 6 档缆绳长度，而伸多长是玩法说了算的。
# 所以拆成「缆绳的一行」和「爪子」两张图，缆绳竖着平铺到要的长度，爪子贴在末端。
# 取爪子用缆绳最长的那一帧（Up-Down 帧 2），合拢的爪子用 Attack4 最后一帧。
BOSS2_ARM = {"open": ("Up-Down.png", 2), "shut": ("Attack4.png", 5)}
# 爪子横向占的那一段（六帧都一样），以及缆绳取第几行（中段，随便哪一行都能无缝平铺）。
BOSS2_CLAW_X = (28, 68)
BOSS2_CABLE_ROW = 32


def build_boss_operator(write):
	# **不能用 frames_of**：它按 `CELL`（48）切，而 Boss 每帧是 96
	def frames_at(file_name, indices):
		_, _, pixels = sb.read_png(os.path.join(BOSS2_DIR, file_name))
		return [sb.cut(pixels, i * BOSS2_CELL, 0, BOSS2_CELL, BOSS2_CELL) for i in indices]

	clips = {c: frames_at(f, idx) for c, (f, idx) in BOSS2_CLIPS.items()}
	for name, frames in clips.items():
		right = [sb.blank(BOSS2_CELL, BOSS2_CELL) for _ in frames]
		for out_frame, f in zip(right, frames):
			sb.blit(out_frame, f, 0, 0, "2_boss %s" % name)
		left = [mirror_about(f, BOSS2_ANCHOR[0]) for f in right]
		save_frames(BOSS2_OUT, "%s_r.png" % name, right, BOSS2_CELL, BOSS2_CELL, write, IND_OUT)
		save_frames(BOSS2_OUT, "%s_l.png" % name, left, BOSS2_CELL, BOSS2_CELL, write, IND_OUT)
	portrait = sb.cut(clips["idle"][0], *BOSS2_PORTRAIT)
	if write:
		sb.write_png(os.path.join(IND_OUT, BOSS2_OUT, "portrait.png"), portrait)
	print("  %s/portrait.png  %dx%d" % (BOSS2_OUT, len(portrait[0]), len(portrait)))

	# 手臂：缆绳一行 + 张开的爪 + 合拢的爪。三张都按缆绳中心那一列对齐，
	# 这样游戏里「从球底往下画缆绳、末端贴爪子」不用再算偏移。
	left_x, right_x = BOSS2_CLAW_X
	for key, (file_name, index) in BOSS2_ARM.items():
		frame = frames_at(file_name, [index])[0]
		rows = [y for y in range(BOSS2_CELL)
			if sum(1 for x in range(BOSS2_CELL) if frame[y][x][3] > 8) > 6 and y > 20]
		claw = sb.blank(right_x - left_x, max(rows) - min(rows) + 1)
		sb.blit(claw, sb.cut(frame, left_x, min(rows), right_x - left_x, len(claw)), 0, 0, "claw")
		if write:
			sb.write_png(os.path.join(IND_OUT, BOSS2_OUT, "arm_claw_%s.png" % key), claw)
		print("  %s/arm_claw_%s.png  %dx%d" % (BOSS2_OUT, key, len(claw[0]), len(claw)))
	cable_frame = frames_at(BOSS2_ARM["open"][0], [BOSS2_ARM["open"][1]])[0]
	# 缆绳只取它自己那几列（4px 宽），不带爪子那一整条：
	# 游戏里缆绳是**按中心**往下画的，图里留着两边的空白会让它看着往一边偏。
	row = cable_frame[BOSS2_CABLE_ROW]
	columns = [x for x in range(BOSS2_CELL) if row[x][3] > 8]
	cable = sb.blank(max(columns) - min(columns) + 1, 1)
	sb.blit(cable, sb.cut(cable_frame, min(columns), BOSS2_CABLE_ROW, len(cable[0]), 1), 0, 0, "cable")
	if write:
		sb.write_png(os.path.join(IND_OUT, BOSS2_OUT, "arm_cable.png"), cable)
	print("  %s/arm_cable.png  %dx1（竖着平铺，按中心画）" % (BOSS2_OUT, len(cable[0])))


# ---------------------------------------------------------------- 酒吧街（第三关）
# 素材 CraftPix Bar Street Enemies（不进仓库）。格式还是 48×48、脚底在帧底边，
# 所以六个全部走 `build_singles`——这一关没有会飞的（5 号鲨鱼机**固定在地面**，贴着地面开枪）。
#
# **2 号枪手自带三个瞄准角度**（Attack1 水平 / Attack2 斜上 / Attack3 斜下），
# 正好对上引擎已有的 `attack_level` / `attack_up` / `attack_down`——
# 第二关那个 2-C 缺的就是这套，所以它斜着打时画面是水平端枪的（见「工业区素材包」）。
BAR_PACK = os.path.join(HERE, "..", "art_in", "default", "bar-street-tileset", "enemies")
BAR_OUT = os.path.join(HERE, "..", "skins", "bar_street", "enemies")
BAR_SINGLES = {
	# 3-A 刀客：蓄一下然后急冲一段去刺。冲的那一段用走路那组放快（`run` 12fps）。
	"3_a": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 3-B 枪手：巡逻 + 射击 + **真斜射**（三个角度都是素材自带的）。
	"3_b": ("2", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack1.png", [0, 1, 2, 3]),
		"attack_up": ("Attack2.png", [0, 1, 2, 3]),
		"attack_down": ("Attack3.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 3-C 剑客：跳向玩家、落地横扫。**空中用挥剑那组第 1 帧**（举剑的姿势），
	# 素材没有专门的跳跃帧，拿走路那组当空中会看着像在平地上溜。
	"3_c": ("3", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Attack.png", [0]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3]),
	}),
	# 3-D 壮汉：正面扛伤害的那个，走得不快、也不冲锋。
	"3_d": ("4", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 3-E 鲨鱼机：**固定在地面**，贴着地面开枪。不走路，所以 `walk` 不取。
	# 它只有 11px 高，趴在地上——按「躯干」定位的话那条带里一个像素都没有，所以按外框居中。
	"3_e": ("5", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"attack_level": ("Attack.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}, "box"),
	# 3-F 炮车：带轮子的炮台，走得很慢，停下来打一串。
	"3_f": ("6", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3]),
	}),
}


# ---------------------------------------------------------------- 酒吧街的 Boss（独轮机甲）
# 素材 `bosses/3`。每帧 96×96、机体约 53×64、踩在一个独轮上，**脚底在帧底边**。
# 判定框 48×56（比画面小一圈，和前两个 Boss 一样），输出帧 112×96 留出炮管伸出去的余量。
#
# 这包的命名和内容对不上，**是看图认出来的**：
#   `Attack1` 炮击、`Attack3` 把炸弹往上抛（举臂 + 红色弹道）、
#   `Special` 才是前倾滚动（冲撞那一下）、`Attack4` 其实是**炸弹自己的爆炸动画**（不是 Boss 的动作）。
# 炸弹用现成的敌人手雷（`enemy_grenade.tscn`）：`Grenade.launch()` 本来就是抛物线、落地弹一下再炸，
# 正是「抛到空中砸下来」。`Bomb.png` 那张 96×96 对 8px 的判定来说太大了，没用。
BOSS3_DIR = os.path.join(BAR_PACK, "..", "bosses", "3")
BOSS3_CELL = 96
# **帧要比素材高**：举臂抛弹那组的红色弹道伸到素材画面上方去了，
# 按 96 高输出会把它切掉——那是「要抛炸弹了」的预兆，不能丢。
BOSS3_FRAME_W, BOSS3_FRAME_H = 112, 120
BOSS3_ANCHOR_Y = 68
BOSS3_OUT = "3_boss"
## 脚底落在原点下方多少（= 判定框高的一半）。
BOSS3_FOOT = 28
BOSS3_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3, 4, 5]),
	"walk": ("Walk.png", [0, 1, 2, 3]),
	"run": ("Special.png", [0, 1, 2, 3, 4, 5]),        # 前倾滚动 = 冲撞
	"attack_level": ("Attack1.png", [0, 1, 2, 3, 4, 5]),
	"attack_up": ("Attack3.png", [0, 1, 2, 3, 4, 5]),  # 举臂往上抛炸弹
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## HUD 头像：机体上半部那 32×32（座舱和那根天线）。
BOSS3_PORTRAIT = (20, 34, 32, 32)


def build_boss_wheel(write):
	def frames_at(file_name, indices):
		_, _, pixels = sb.read_png(os.path.join(BOSS3_DIR, file_name))
		return [sb.cut(pixels, i * BOSS3_CELL, 0, BOSS3_CELL, BOSS3_CELL) for i in indices]

	clips = {c: frames_at(f, idx) for c, (f, idx) in BOSS3_CLIPS.items()}
	# 整组只按待机第一帧定一次位（和前两个 Boss 一样）：横向按机体外框居中，
	# 纵向让脚底落在原点下方 BOSS3_FOOT。
	first = clips["idle"][0]
	xs = [x for row in first for x, c in enumerate(row) if c[3] > 8]
	dx = BOSS3_FRAME_W // 2 - int(round((min(xs) + max(xs)) / 2.0))
	dy = BOSS3_ANCHOR_Y + BOSS3_FOOT - BOSS3_CELL
	for name, frames in clips.items():
		right = []
		for f in frames:
			out = sb.blank(BOSS3_FRAME_W, BOSS3_FRAME_H)
			sb.blit(out, f, dx, dy, "3_boss %s" % name)
			right.append(out)
		left = [mirror_about(f, BOSS3_FRAME_W // 2) for f in right]
		save_frames(BOSS3_OUT, "%s_r.png" % name, right, BOSS3_FRAME_W, BOSS3_FRAME_H, write, BAR_OUT)
		save_frames(BOSS3_OUT, "%s_l.png" % name, left, BOSS3_FRAME_W, BOSS3_FRAME_H, write, BAR_OUT)
	x, y, w, h = BOSS3_PORTRAIT
	portrait = sb.cut(clips["idle"][0], x, y, w, h)
	if write:
		sb.write_png(os.path.join(BAR_OUT, BOSS3_OUT, "portrait.png"), portrait)
	print("  %s/portrait.png  %dx%d" % (BOSS3_OUT, w, h))


# ---------------------------------------------------------------- 地下室（第四关，纵向往上爬）
# 素材 CraftPix Basement Enemies（`basement-tileset/enemies/`，不进仓库），格式还是 48×48、脚底在帧底边。
# 打法 2026-10 和用户一起定的（这一关往上爬，威胁要从上下和侧面来）：
BASE_PACK = os.path.join(HERE, "..", "art_in", "default", "basement-tileset", "enemies")
BASE_OUT = os.path.join(HERE, "..", "skins", "basement", "enemies")
BASE_SINGLES = {
	# 4-A 光膀子打手：**从下面追上来的追兵**（D 那套，能一层层跳上平台）。
	# Walk 那组画的就是冲刺（身子前倾、胳膊甩开），走和冲用同一组；空中取其中一帧。
	"4_a": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"run": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"air": ("Walk.png", [2]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 4-B 猫耳女：**平台守卫**。Attack 6 帧 = 甩一下、举过头顶（第 3、4 帧，蓄力）、
	# **第 5 帧刀光横扫到最远**——伤害卡这一帧。
	"4_b": ("2", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 4-C 西装男：三向枪手。素材自带水平 / 斜上 / 斜下三组，和第三关 3-B 一样是真斜射。
	"4_c": ("3", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack1.png", [0, 1, 2, 3]),
		"attack_up": ("Attack2.png", [0, 1, 2, 3]),
		"attack_down": ("Attack3.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 4-E 蜘蛛炮台：守层炮台，慢慢挪、横着打一串。不是人形，按外框居中。
	"4_e": ("5", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}, "box"),
	# 4-F 骷髅衫打手：**一拳打下平台**。Attack 6 帧里第 5 帧整条胳膊横甩到最远——击退卡这一帧。
	"4_f": ("6", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}
# 4-D 无人机：**贴着玩家的高度飞**、对齐了就横着开枪。素材是**朝左**画的（枪管在左），
# 生成时先翻过来。机身是第 19~30 行（上面是天线、下面是喷口）。
# 它的 Attack 只是底下喷口闪一下、没画枪口火光——开火那团光由特效层（`Fx`）另外画。
BASE_FLYER_BODY = (19, 30)
BASE_FLYER = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"attack_level": ("Attack.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}


# ---------------------------------------------------------------- 地下室的 Boss（骷髅头）
# 素材 `bosses/2`。每帧 96×96，一个漂着的大骷髅头 + 一只骨手，身子在帧里的 x 10..53、y 23..77，
# **中心约在 (32, 50)**。动作是看图认的：
#   Attack1 / Attack2 两组几乎一样：前两帧蓄力、第 3、4 帧从骨手里射出一道**水平激光**（红黑条纹）；
#   Attack3：身边冒出红球，第 5 帧手里掉出一个**小骷髅**——召唤；
#   Idle2 / Walk2 / Hurt2 / Death2 是 48×48 的**小骷髅**本身（召唤出来的小兵）；
#   Sneer：收起骨手只剩骷髅头——嘲讽，用在血过半换挡那一下。
#
# **输出帧 128×96、锚点 (64, 48)**：素材里激光那一截伸到画面右边缘（x 95），往右挪 32 对准锚点之后
# 到了 127；左右镜像要绕锚点翻，所以左边也得留出同样的宽度。
# 激光本身由外观按玩法给的长度另外画（`BossSkullAppearance`），素材里那一截只是开头。
BOSS4_DIR = os.path.join(BASE_PACK, "..", "bosses", "2")
BOSS4_OUT = "4_boss"
BOSS4_CELL = 96
BOSS4_FRAME_W = 128
BOSS4_FRAME_H = 96
BOSS4_ANCHOR = (64, 48)
## 素材里身子的中心（对准锚点的那一点）。
BOSS4_BODY = (32, 50)
BOSS4_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3]),
	"charge": ("Attack1.png", [0, 1]),
	"beam": ("Attack1.png", [2, 3]),
	"summon": ("Attack3.png", [0, 1, 2, 3, 4, 5]),
	"sneer": ("Sneer.png", [0, 1, 2, 3, 4, 5]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## 激光那一条：从 Attack1 的出光帧里取一列（x 90）。粗的那档是第 3 帧（6 行），快收的时候第 4 帧（4 行）。
BOSS4_BEAM = {"beam_thick": (2, 63, 69), "beam_thin": (3, 64, 68)}
BOSS4_BEAM_COLUMN = 90
## HUD 头像：骷髅那一块。
BOSS4_PORTRAIT = (16, 22, 32, 32)
## 小骷髅（48×48，中心约在 (23, 23)），走会飞的那条路：身子是第 17~30 行。
MINION4_OUT = "4_minion"
MINION4_BODY = (17, 30)
MINION4 = {
	"idle": ("Idle2.png", [0, 1, 2, 3]),
	"walk": ("Walk2.png", [0, 1, 2, 3]),
	"hurt": ("Hurt2.png", [0, 1]),
	"death": ("Death2.png", [0, 1, 2, 3]),
}


def build_boss_skull(write):
	dx = BOSS4_ANCHOR[0] - BOSS4_BODY[0]
	dy = BOSS4_ANCHOR[1] - BOSS4_BODY[1]
	for name, (f, idx) in BOSS4_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(BOSS4_DIR, f))
		right = []
		for i in idx:
			frame = sb.cut(pixels, i * BOSS4_CELL, 0, BOSS4_CELL, BOSS4_CELL)
			placed = sb.blank(BOSS4_FRAME_W, BOSS4_FRAME_H)
			sb.blit(placed, frame, dx, dy, "boss4 %s" % name)
			right.append(placed)
		left = [mirror_about(fr, BOSS4_ANCHOR[0]) for fr in right]
		save_frames(BOSS4_OUT, "%s_r.png" % name, right, BOSS4_FRAME_W, BOSS4_FRAME_H, write, BASE_OUT)
		save_frames(BOSS4_OUT, "%s_l.png" % name, left, BOSS4_FRAME_W, BOSS4_FRAME_H, write, BASE_OUT)
	_, _, attack = sb.read_png(os.path.join(BOSS4_DIR, "Attack1.png"))
	for name, (frame, top, bottom) in BOSS4_BEAM.items():
		column = [[attack[y][frame * BOSS4_CELL + BOSS4_BEAM_COLUMN]] for y in range(top, bottom)]
		if write:
			sb.write_png(os.path.join(BASE_OUT, BOSS4_OUT, name + ".png"), column)
		print("  %s/%s.png  1x%d" % (BOSS4_OUT, name, bottom - top))
	_, _, idle = sb.read_png(os.path.join(BOSS4_DIR, "Idle.png"))
	x, y, w, h = BOSS4_PORTRAIT
	if write:
		sb.write_png(os.path.join(BASE_OUT, BOSS4_OUT, "portrait.png"), sb.cut(idle, x, y, w, h))
	build_flyer(write, MINION4_OUT, ".", MINION4, BOSS4_DIR, BASE_OUT, MINION4_BODY)


# ---------------------------------------------------------------- 实验室（第五关）
# 素材 CraftPix Lab Enemies（`lab-tileset/enemies/`，不进仓库）。1~3 号是 48×48、脚底在帧底边的小个子，走 `build_singles`；
# 4~6 号是 96×96 的炮塔头、`Mech base/` 是底座，叠起来拼成大型机甲（`build_lab_mechs()`）。
LAB_PACK = os.path.join(HERE, "..", "art_in", "default", "lab-tileset", "enemies")
LAB_OUT = os.path.join(HERE, "..", "skins", "lab", "enemies")
LAB_SINGLES = {
	# 5-A 科学家（黑发）：巡逻、往前扔酸液瓶（Attack 第 4 帧胳膊甩到最前——出手卡这一帧）；
	# 挨打或被逼近时**变身**（Transform 4 帧，最后一帧已经是变异体的样子），变完换成 5-C。
	"5_a": ("1", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"transform": ("Transform.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 5-B 科学家（灰发）：一看见玩家就变身。
	"5_b": ("2", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"transform": ("Transform.png", [0, 1, 2, 3]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
	# 5-C 变异体：走近、举手、砸地。Attack 6 帧里第 4 帧（下标 3）大臂砸到地上——伤害和震波卡这一帧。
	"5_c": ("3", "idle", {
		"idle": ("Idle.png", [0, 1, 2, 3]),
		"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
		"attack_level": ("Attack.png", [0, 1, 2, 3, 4, 5]),
		"hurt": ("Hurt.png", [0, 1]),
		"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
	}),
}


## 大型机甲 = 炮塔头（4~6 号）叠在底座（`Mech base/`）上：头的底边在第 62 行、底座从第 61~63 行开始，
## **同一个 96×96 帧里直接叠起来就接上了**，不用挪。输出帧照旧 96×96，锚点是身体中心（外观场景里配）。
## 表：键 → (锚点, 上下翻转没有, {动作: (头的文件, 帧, 底座的文件, 底座帧（None = 每帧用第 0 帧）)})。
## - 5-D 原地炮台：机枪头 + 履带。身子那一列中心在 x 46、脚底在第 72 行 → 锚点 (46, 56)；炮口在 (73, 48)。
## - 5-F 天花板发射器：发射器头 + 小运输车当吊架，**整个上下翻转**（倒挂在天花板上）。
##   翻过来之后吊架在上、头在下，头的中心 (45, 45) 是锚点，吊架顶边（天花板）在锚点上面 20。
LAB_MECHS = {
	"5_d": ((46, 56), False, {
		"idle": ("5/Idle.png", [0, 1, 2, 3, 4, 5], "Mech base/Walk2.png", None),
		"attack_level": ("5/Attack.png", [0, 1, 2, 3, 4, 5], "Mech base/Walk2.png", None),
		"hurt": ("5/Hurt.png", [0, 1], "Mech base/Hurt2.png", [0, 1]),
	}),
	"5_f": ((45, 45), True, {
		"idle": ("4/Idle.png", [0, 1, 2, 3], "Mech base/Hurt3.png", None),
		"attack_level": ("4/Attack.png", [0, 1, 2, 3], "Mech base/Hurt3.png", None),
		"hurt": ("4/Hurt.png", [0, 1], "Mech base/Hurt3.png", [0, 1]),
	}),
}
## 5-E 地下钻出来的蜘蛛爪臂：爪臂头 + 蜘蛛腿。身子那一列中心 x 46、脚底第 76 行 → 锚点 (46, 60)。
## 走路是腿的 6 帧配头的待机 4 帧（轮着用）；攻击那 6 帧爪臂从右边一路扫到左边（第 5、6 帧胳膊甩到另一侧），
## 玩法里一边转身一边播，正好是「原地转一圈扫两边」。
## `emerge`（钻出来）是这里拼出来的：前 4 帧地上那块**履带**往旁边滑开，后 4 帧机甲从地板下面升上来
## （地板线以下的像素切掉）。埋着的时候停在第 1 帧——地上只有一块履带，那就是给玩家的提醒。
LAB_BURROWER = {
	"anchor": (46, 60),
	"floor": 76,
	"idle": ("6/Idle.png", [0, 1, 2, 3], "Mech base/Walk1.png", [0]),
	"walk": ("6/Idle.png", [0, 1, 2, 3, 0, 1], "Mech base/Walk1.png", [0, 1, 2, 3, 4, 5]),
	"attack_level": ("6/Attack.png", [0, 1, 2, 3, 4, 5], "Mech base/Walk1.png", [0]),
	"hurt": ("6/Hurt.png", [0, 1], "Mech base/Hurt1.png", [0, 1]),
	# 履带（`Walk2` 第 1 帧，第 63~71 行）往右滑开多远、机甲每帧还埋在地下多深
	"hatch": ("Mech base/Walk2.png", 0),
	"hatch_slide": [0, 8, 16, 26, 28, 28, 28, 28],
	"rise": [None, None, None, None, 40, 28, 16, 6],
}
MECH_CELL = 96
## 5-F 滴下来的那滴毒液：`Acid1` 第 1 帧里那滴（带长尾巴，25×59）只取下面 30 行——一个球带一小截尾巴。
POISON_DRIP = ("Acid1.png", (24, 30, 25, 30))


def build_lab_mechs(write):
	def frames_of_cell(rel, indices):
		_, _, pixels = sb.read_png(os.path.join(LAB_PACK, *rel.split("/")))
		return [sb.cut(pixels, i * MECH_CELL, 0, MECH_CELL, MECH_CELL) for i in indices]

	for key, (anchor, flip, clips) in LAB_MECHS.items():
		for clip, (head_rel, head_idx, base_rel, base_idx) in clips.items():
			heads = frames_of_cell(head_rel, head_idx)
			bases = frames_of_cell(base_rel, base_idx if base_idx is not None else [0])
			right = []
			for i, head in enumerate(heads):
				frame = sb.blank(MECH_CELL, MECH_CELL)
				sb.blit(frame, bases[i % len(bases)], 0, 0, "%s %s base" % (key, clip))
				sb.blit(frame, head, 0, 0, "%s %s head" % (key, clip))
				if flip:
					frame = frame[::-1]
				right.append(frame)
			left = [mirror_about(f, anchor[0]) for f in right]
			save_frames(key, "%s_r.png" % clip, right, MECH_CELL, MECH_CELL, write, LAB_OUT)
			save_frames(key, "%s_l.png" % clip, left, MECH_CELL, MECH_CELL, write, LAB_OUT)
	build_lab_burrower(write, frames_of_cell)
	rel, (x, y, w, h) = POISON_DRIP
	_, _, pixels = sb.read_png(os.path.join(LAB_PACK, "..", "4 Animated objects", rel))
	drip = sb.cut(pixels, x, y, w, h)
	out = os.path.join(HERE, "..", "skins", "lab", "projectiles", "poison_drip", "spin.png")
	if write:
		sb.write_png(out, drip)
	print("  projectiles/poison_drip/spin.png  %dx%d" % (w, h))


def build_lab_burrower(write, frames_of_cell):
	spec = LAB_BURROWER
	anchor, floor = spec["anchor"], spec["floor"]

	def stack(head, base):
		frame = sb.blank(MECH_CELL, MECH_CELL)
		sb.blit(frame, base, 0, 0, "5_e base")
		sb.blit(frame, head, 0, 0, "5_e head")
		return frame

	clips = {}
	for clip in ("idle", "walk", "attack_level", "hurt"):
		head_rel, head_idx, base_rel, base_idx = spec[clip]
		heads = frames_of_cell(head_rel, head_idx)
		bases = frames_of_cell(base_rel, base_idx)
		clips[clip] = [stack(h, bases[i % len(bases)]) for i, h in enumerate(heads)]
	clips["run"] = clips["walk"]
	# 钻出来：履带滑开，机甲从地板下升上来
	hatch_rel, hatch_frame = spec["hatch"]
	hatch = frames_of_cell(hatch_rel, [hatch_frame])[0]
	# 履带底边在第 71 行，往下挪到正好躺在地板线上
	hatch_drop = floor - 72
	mech = clips["idle"][0]
	emerge = []
	for slide, sunk in zip(spec["hatch_slide"], spec["rise"]):
		frame = sb.blank(MECH_CELL, MECH_CELL)
		if sunk is not None:
			for yy in range(MECH_CELL):
				ty = yy + sunk
				if ty >= floor or ty >= MECH_CELL:
					continue
				for xx in range(MECH_CELL):
					if mech[yy][xx][3] > 8:
						frame[ty][xx] = mech[yy][xx]
		for yy in range(MECH_CELL):
			ty = yy + hatch_drop
			if not 0 <= ty < MECH_CELL:
				continue
			for xx in range(MECH_CELL):
				tx = xx + slide
				if hatch[yy][xx][3] > 8 and 0 <= tx < MECH_CELL:
					frame[ty][tx] = hatch[yy][xx]
		emerge.append(frame)
	clips["emerge"] = emerge
	for clip, right in clips.items():
		left = [mirror_about(f, anchor[0]) for f in right]
		save_frames("5_e", "%s_r.png" % clip, right, MECH_CELL, MECH_CELL, write, LAB_OUT)
		save_frames("5_e", "%s_l.png" % clip, left, MECH_CELL, MECH_CELL, write, LAB_OUT)


# ---------------------------------------------------------------- 实验室的中段小 Boss（变异枪手，`boss/1`）
# 每帧 72×72、身子在 x 9..44、脚底在帧底边；身子那一列（腿）中心 x 25。动作是看图认的：
#   Attack1 站着开激光（第 4 帧粗白光、第 5 帧细绿光，打到帧边）、Attack2 边走边开、Attack3 前踢、
#   Attack4 往前一顶（枪托冲撞）、Special 枪身微微一抬（蓄力，当预警用）。
# **输出帧 128×72、锚点 (64, 48)**：激光那一截伸到素材帧边（x 71），往右挪 39 对准锚点后到 110，
# 左右镜像绕锚点翻，两边都得留这么宽。判定框 32×48（脚底在原点下方 24）。
# 激光本身由外观按玩法给的长度另外画（和地下室骷髅头一个做法）：取出光那两帧的一列。
LAB_MIDBOSS_DIR = os.path.join(LAB_PACK, "..", "boss", "1")
LAB_MIDBOSS_OUT = "5_midboss"
LAB_MIDBOSS_CELL = 72
LAB_MIDBOSS_FRAME = (128, 72)
LAB_MIDBOSS_ANCHOR = (64, 48)
LAB_MIDBOSS_BODY_X = 25
LAB_MIDBOSS_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3, 4, 5]),
	"charge": ("Special.png", [0, 1, 2, 3]),
	"beam": ("Attack1.png", [3, 4]),
	"attack_level": ("Attack1.png", [0, 1, 2, 3, 4, 5]),
	"attack_walk": ("Attack2.png", [0, 1, 2, 3, 4, 5]),
	"kick": ("Attack3.png", [0, 1, 2, 3, 4, 5]),
	"lunge": ("Attack4.png", [0, 1, 2, 3, 4, 5]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## 激光那一条：Attack1 出光帧里 x 60 那一列。粗的是第 4 帧（第 41~45 行），细的是第 5 帧。
LAB_MIDBOSS_BEAM = {"beam_thick": (3, 41, 46), "beam_thin": (4, 42, 45)}
LAB_MIDBOSS_BEAM_COLUMN = 60
## HUD 头像：头和枪那一块。
LAB_MIDBOSS_PORTRAIT = (12, 20, 32, 32)


def build_lab_midboss(write):
	dx = LAB_MIDBOSS_ANCHOR[0] - LAB_MIDBOSS_BODY_X
	fw, fh = LAB_MIDBOSS_FRAME
	for name, (f, idx) in LAB_MIDBOSS_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(LAB_MIDBOSS_DIR, f))
		right = []
		for i in idx:
			frame = sb.cut(pixels, i * LAB_MIDBOSS_CELL, 0, LAB_MIDBOSS_CELL, LAB_MIDBOSS_CELL)
			placed = sb.blank(fw, fh)
			sb.blit(placed, frame, dx, 0, "midboss %s" % name)
			right.append(placed)
		left = [mirror_about(fr, LAB_MIDBOSS_ANCHOR[0]) for fr in right]
		save_frames(LAB_MIDBOSS_OUT, "%s_r.png" % name, right, fw, fh, write, LAB_OUT)
		save_frames(LAB_MIDBOSS_OUT, "%s_l.png" % name, left, fw, fh, write, LAB_OUT)
	_, _, attack = sb.read_png(os.path.join(LAB_MIDBOSS_DIR, "Attack1.png"))
	for name, (frame, top, bottom) in LAB_MIDBOSS_BEAM.items():
		column = [[attack[y][frame * LAB_MIDBOSS_CELL + LAB_MIDBOSS_BEAM_COLUMN]] for y in range(top, bottom)]
		if write:
			sb.write_png(os.path.join(LAB_OUT, LAB_MIDBOSS_OUT, name + ".png"), column)
		print("  %s/%s.png  1x%d" % (LAB_MIDBOSS_OUT, name, bottom - top))
	_, _, idle = sb.read_png(os.path.join(LAB_MIDBOSS_DIR, "Idle.png"))
	x, y, w, h = LAB_MIDBOSS_PORTRAIT
	if write:
		sb.write_png(os.path.join(LAB_OUT, LAB_MIDBOSS_OUT, "portrait.png"), sb.cut(idle, x, y, w, h))
	print("  %s/portrait.png  %dx%d" % (LAB_MIDBOSS_OUT, w, h))


## 关底 Boss「生化舱」（素材 `boss/3`）：飞着的，朝右（推进器在左边）。帧 72×72，机身中心在 (26, 34)。
## 输出帧 144×96、锚点 (72, 48) 放在机身中心——激光和炮口闪光伸到素材右边缘，镜像时两边都得留出来。
## 文件名对内容：Attack1/2 一样是眼睛打水平激光，Attack3 缩成圆壳，Attack4_1/2/3 是正下 / 斜下 / 水平三门炮，
## Special 是叶片转一圈（换位置时播），Death 掉下去摔成两半。
LAB_POD_DIR = os.path.join(LAB_PACK, "..", "boss", "3")
LAB_POD_OUT = "5_boss"
LAB_POD_CELL = 72
LAB_POD_FRAME = (144, 96)
LAB_POD_ANCHOR = (72, 48)
LAB_POD_CENTER = (26, 34)
LAB_POD_CLIPS = {
	"idle": ("Idle.png", [0, 1, 2, 3]),
	"walk": ("Walk.png", [0, 1, 2, 3]),
	"charge": ("Attack1.png", [0, 1]),
	"beam": ("Attack1.png", [3, 4]),
	"shell": ("Attack3.png", [2, 3, 4, 5]),
	"cannon_down": ("Attack4_1.png", [0, 1, 2, 3]),
	"cannon_diag": ("Attack4_2.png", [0, 1, 2, 3]),
	"cannon_level": ("Attack4_3.png", [0, 1, 2, 3]),
	"spin": ("Special.png", [0, 1, 2, 3]),
	"hurt": ("Hurt.png", [0, 1]),
	"death": ("Death.png", [0, 1, 2, 3, 4, 5]),
}
## 激光那一条：Attack1 出光帧里 x 70 那一列。粗的是第 4 帧（第 30~41 行），细的是第 6 帧（第 32~37 行）。
LAB_POD_BEAM = {"beam_thick": (3, 30, 42), "beam_thin": (5, 32, 38)}
LAB_POD_BEAM_COLUMN = 70
## HUD 头像：眼睛那一块。
LAB_POD_PORTRAIT = (12, 18, 32, 32)


def build_lab_pod(write):
	dx = LAB_POD_ANCHOR[0] - LAB_POD_CENTER[0]
	dy = LAB_POD_ANCHOR[1] - LAB_POD_CENTER[1]
	fw, fh = LAB_POD_FRAME
	for name, (f, idx) in LAB_POD_CLIPS.items():
		_, _, pixels = sb.read_png(os.path.join(LAB_POD_DIR, f))
		right = []
		for i in idx:
			frame = sb.cut(pixels, i * LAB_POD_CELL, 0, LAB_POD_CELL, LAB_POD_CELL)
			placed = sb.blank(fw, fh)
			sb.blit(placed, frame, dx, dy, "pod %s" % name)
			right.append(placed)
		left = [mirror_about(fr, LAB_POD_ANCHOR[0]) for fr in right]
		save_frames(LAB_POD_OUT, "%s_r.png" % name, right, fw, fh, write, LAB_OUT)
		save_frames(LAB_POD_OUT, "%s_l.png" % name, left, fw, fh, write, LAB_OUT)
	_, _, attack = sb.read_png(os.path.join(LAB_POD_DIR, "Attack1.png"))
	for name, (frame, top, bottom) in LAB_POD_BEAM.items():
		column = [[attack[y][frame * LAB_POD_CELL + LAB_POD_BEAM_COLUMN]] for y in range(top, bottom)]
		if write:
			sb.write_png(os.path.join(LAB_OUT, LAB_POD_OUT, name + ".png"), column)
		print("  %s/%s.png  1x%d" % (LAB_POD_OUT, name, bottom - top))
	_, _, idle = sb.read_png(os.path.join(LAB_POD_DIR, "Idle.png"))
	x, y, w, h = LAB_POD_PORTRAIT
	if write:
		sb.write_png(os.path.join(LAB_OUT, LAB_POD_OUT, "portrait.png"), sb.cut(idle, x, y, w, h))
	print("  %s/portrait.png  %dx%d" % (LAB_POD_OUT, w, h))


def build_lab(write):
	if not os.path.isdir(LAB_PACK):
		sys.exit("找不到实验室敌人素材 %s（不在仓库里，要自己解压进去）" % os.path.normpath(LAB_PACK))
	build_singles(write, LAB_SINGLES, LAB_PACK, LAB_OUT)
	build_lab_mechs(write)
	build_lab_midboss(write)
	build_lab_pod(write)


def build_basement(write):
	if not os.path.isdir(BASE_PACK):
		sys.exit("找不到地下室敌人素材 %s（不在仓库里，要自己解压进去）" % os.path.normpath(BASE_PACK))
	build_singles(write, BASE_SINGLES, BASE_PACK, BASE_OUT)
	build_flyer(write, "4_d", "4", BASE_FLYER, BASE_PACK, BASE_OUT, BASE_FLYER_BODY, faces_left=True)
	build_boss_skull(write)


def build_industrial(write):
	if not os.path.isdir(IND_PACK):
		sys.exit("找不到工业区敌人素材 %s（不在仓库里，要自己解压进去）" % os.path.normpath(IND_PACK))
	build_singles(write, IND_SINGLES, IND_PACK, IND_OUT)
	build_flyer(write, "2_e", "5 Copter", IND_FLYER, IND_PACK, IND_OUT, IND_FLYER_BODY)
	build_boss_operator(write)


def build_bar_street(write):
	if not os.path.isdir(BAR_PACK):
		sys.exit("找不到酒吧街敌人素材 %s（不在仓库里，要自己解压进去）" % os.path.normpath(BAR_PACK))
	build_singles(write, BAR_SINGLES, BAR_PACK, BAR_OUT)
	build_boss_wheel(write)


def main():
	write = "--check" not in sys.argv
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	if only == ["lab"]:
		print("实验室（第五关）的敌人：")
		build_lab(write)
		_report(write)
		return
	if only == ["basement"]:
		print("地下室（第四关）的六种敌人：")
		build_basement(write)
		_report(write)
		return
	if only == ["bar_street"]:
		print("酒吧街（第三关）的六种敌人：")
		build_bar_street(write)
		_report(write)
		return
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
	print("酒吧街（第三关）的六种敌人：")
	build_bar_street(write)
	print("地下室（第四关）的六种敌人：")
	build_basement(write)
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
