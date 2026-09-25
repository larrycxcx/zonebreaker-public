class_name UiKit
extends RefCounted
## 界面的共用零件：字体、窗口九宫格、颜色，以及几个「照这个样子做一个控件」的小工厂。
##
## 素材由 `tools/ui_build.py` 从 gui 素材包生成到 `skins/cyberpunk/ui/`：
## 字体是位图字体（`.fnt`，Godot 直接当 FontFile 导入），字模抠出来是白的，用 `modulate` 染色。
## **界面一律英文大写**——素材包的字模只有 A–Z、0–9 和一些符号，没有汉字（见 CLAUDE.md）。
##
## 界面用的美术目前直接引用这个目录，还没进 `SkinPack`。以后要让素材包也能换界面皮肤时再收进去，
## 那时只要把下面这几个常量改成问 `Skins` 要。

const DIR := "res://skins/cyberpunk/ui"
const FONT := DIR + "/font.fnt"
## 正文那套小一号的字模（10px）。**位图字体只有做出来的那一个尺寸是清楚的**，
## 所以正文和标题各用各的图集，不让引擎去缩（非整数倍缩放会糊）。
const FONT_SMALL := DIR + "/font_small.fnt"
const PANEL := DIR + "/panel.png"
const PANEL_FILL := DIR + "/panel_fill.png"
const CURSOR := DIR + "/cursor.png"
const PLUS := DIR + "/plus.png"
## 九宫格四条边各占几像素（`panel.png` 是 3×3 块 32px 拼的）。
const PANEL_MARGIN := 32
## 正文字号 = 小那套字模的原尺寸。14 那套在 640×360 上太占地方，一行字比角色的脑袋还高。
const TEXT_SIZE := 10
## 标题字号 = 大那套字模（14）的整数倍。
const TITLE_SIZE := 28

const WHITE := Color(0.925, 0.941, 0.973)
const DIM := Color(0.471, 0.518, 0.659)
const CYAN := Color(0.471, 0.863, 0.922)
const GOLD := Color(0.961, 0.784, 0.353)
const GREEN := Color(0.549, 0.902, 0.627)
## 四个属性各自的颜色，和加点界面里的图标一致。
const STAT_COLORS := {
	&"life": Color(0.941, 0.431, 0.471),
	&"attack": Color(0.961, 0.667, 0.353),
	&"defense": Color(0.471, 0.745, 0.941),
	&"speed": Color(0.549, 0.902, 0.627),
}


## 这个字号该用哪张图集：标题用 14 那套，正文用 10 那套。两套都只按整数倍放大。
## 界面上的数字：**过千就写成 K**。经验和金钱到后面都是五六位数（一周目总收入九万），
## 原样写会把一行字撑爆，读起来也累。
## 1000 以下原样；一万以下留一位小数（`1.2K`，整数的不留 `.0`）；再往上取整（`13K`、`154K`）。
static func number(value: int) -> String:
	if value < 1000:
		return str(value)
	if value < 1000000:
		var thousands := value / 1000.0
		if thousands < 10.0 and not is_equal_approx(thousands, roundf(thousands)):
			return "%.1fK" % thousands
		return "%dK" % roundi(thousands)
	var millions := value / 1000000.0
	if millions < 10.0 and not is_equal_approx(millions, roundf(millions)):
		return "%.1fM" % millions
	return "%dM" % roundi(millions)


static func font(size := TEXT_SIZE) -> Font:
	return load(FONT if size >= TITLE_SIZE else FONT_SMALL) as Font


## 一个不挡鼠标的文字控件。`box` 是它在父节点里占的矩形。
static func label(text: String, box: Rect2, tint := WHITE, size := TEXT_SIZE,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font(size))
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", tint)
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = box.position
	node.size = box.size
	return node


## 一个窗口：**先用中间那格铺满整块，再把九宫格边框盖上去**。
## 只画九宫格的话，边框图的内沿和中间那格之间会露出一圈缝（窗口越小越明显）。
static func window(box: Rect2) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = box.position
	root.size = box.size
	var fill := TextureRect.new()
	fill.texture = load(PANEL_FILL) as Texture2D
	fill.stretch_mode = TextureRect.STRETCH_TILE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2.ZERO
	fill.size = box.size
	root.add_child(fill)
	var frame := NinePatchRect.new()
	frame.texture = load(PANEL) as Texture2D
	frame.patch_margin_left = PANEL_MARGIN
	frame.patch_margin_top = PANEL_MARGIN
	frame.patch_margin_right = PANEL_MARGIN
	frame.patch_margin_bottom = PANEL_MARGIN
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2.ZERO
	frame.size = box.size
	root.add_child(frame)
	return root


## 一张小图（属性图标、加号、光标）。白色剪影用 tint 染色。
## `path` 留空就是一个先空着的框（贴图之后再填，比如装备格）。
static func picture(path: String, at: Vector2, tint := WHITE) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(path) as Texture2D if not path.is_empty() else null
	node.modulate = tint
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = at
	return node


## 一个小方框（描边 + 填充）。**小格子别用 `window()`**：九宫格那张图是 96×96、四边 32，
## 撑不到 64×64 以下，头像格、装备格那种 30~40px 的框会被撑爆、糊成一片。
static func box(rect: Rect2, edge := Color(0.27, 0.35, 0.55), fill := Color(0.12, 0.15, 0.28)) -> Control:
	var frame := ColorRect.new()
	frame.color = edge
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = rect.position
	frame.size = rect.size
	var inside := ColorRect.new()
	inside.color = fill
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.position = Vector2.ONE
	inside.size = rect.size - Vector2.ONE * 2.0
	frame.add_child(inside)
	return frame


## 人物选择界面上的头像：**素材包里现成的一张图**（`skins/<包>/<角色>/portrait.png`，
## 由 `tools/skin_build.py` 的 `build_portrait()` 从素材原本的待机第一帧裁出来）。
##
## **不能拿游戏里那张身体贴图来画**：那是脱过胳膊的（胳膊按瞄准方向单独烘，见 `strip_arms()`），
## 头像上的人会空着两只袖子（2026-09 试玩看出来的）。也不要把瞄准手臂贴回去——
## 那会带出一根伸到框外的枪管，而且 `strip_arms()` 只脱得干净 biker，
## punk 和 cyborg 的胳膊是袖子和护甲的颜色、和躯干同色又连在一起，脱不掉，
## 贴上去就成了三条胳膊。选人的时候要看的是这个人长什么样，用素材原画最省事也最像。
##
## **按当前皮肤包的目录找**，不写死哪个包：DLC 角色的贴图可能在另一个包里。
## 包里没有这张图就返回 null（界面上那一格空着，不崩）。
static func portrait(look: StringName) -> Texture2D:
	# **要顺着 fallback 找**，不能只看当前包的目录：每关的包只装这一关独有的东西，
	# 角色是 23 关共用的、只在最底下那个包里有一份。只看当前包的话，
	# 打完第二关回主菜单时三个头像会全空（试玩发现）。
	var path := Skins.file("%s/portrait.png" % look)
	if path.is_empty():
		path = "res://skins/cyberpunk/%s/portrait.png" % look
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 把整个画面盖暗一层（暂停时后面的关卡还看得见，但不抢眼）。
static func shade(alpha := 0.62) -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(0.04, 0.05, 0.11, alpha)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
