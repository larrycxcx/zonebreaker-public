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
const PANEL := DIR + "/panel.png"
const CURSOR := DIR + "/cursor.png"
const PLUS := DIR + "/plus.png"
## 九宫格四条边各占几像素（`panel.png` 是 3×3 块 32px 拼的）。
const PANEL_MARGIN := 32
## 正文字号。位图字体只有一个尺寸，放大只能整数倍。
const TEXT_SIZE := 14
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


static func font() -> Font:
	return load(FONT) as Font


## 一个不挡鼠标的文字控件。`box` 是它在父节点里占的矩形。
static func label(text: String, box: Rect2, tint := WHITE, size := TEXT_SIZE,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", tint)
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = box.position
	node.size = box.size
	return node


## 一个窗口（九宫格，四角不拉伸、四边和中间平铺）。
static func window(box: Rect2) -> NinePatchRect:
	var node := NinePatchRect.new()
	node.texture = load(PANEL) as Texture2D
	node.patch_margin_left = PANEL_MARGIN
	node.patch_margin_top = PANEL_MARGIN
	node.patch_margin_right = PANEL_MARGIN
	node.patch_margin_bottom = PANEL_MARGIN
	node.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	node.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = box.position
	node.size = box.size
	return node


## 一张小图（属性图标、加号、光标）。白色剪影用 tint 染色。
static func picture(path: String, at: Vector2, tint := WHITE) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(path) as Texture2D
	node.modulate = tint
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = at
	return node


## 把整个画面盖暗一层（暂停时后面的关卡还看得见，但不抢眼）。
static func shade(alpha := 0.62) -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(0.04, 0.05, 0.11, alpha)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
