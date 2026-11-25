class_name UiKit
extends RefCounted
## Shared UI parts: fonts, the window nine-slice, colours, and a few small factories that "make a control like this".
##
## The art is generated from the gui art pack into `skins/cyberpunk/ui/` by `tools/ui_build.py`:
## the fonts are bitmap fonts (`.fnt`, imported by Godot directly as FontFile), with white glyphs tinted through `modulate`.
## **The UI is always English upper case** — the pack's font only has A–Z, 0–9 and some symbols, no Chinese (see CLAUDE.md).
##
## The UI art is referenced from this folder directly for now and is not in `SkinPack` yet. When skin packs should be able to reskin the UI it moves in,
## and then only these constants need to ask `Skins` instead.
##
## **This folder may be missing**: it is third-party art, stripped from the public build. Then the font falls back to the engine's own
## (`ThemeDB.fallback_font`), windows are drawn as outlined boxes and icons are blank — the UI still works, just not in pixel style.

const DIR := "res://skins/cyberpunk/ui"
const FONT := DIR + "/font.fnt"
## The smaller font for body text (10px). **A bitmap font is only sharp at the one size it was made at**,
## so body text and titles each use their own atlas instead of letting the engine scale (non-integer scaling blurs).
const FONT_SMALL := DIR + "/font_small.fnt"
const PANEL := DIR + "/panel.png"
const PANEL_FILL := DIR + "/panel_fill.png"
const CURSOR := DIR + "/cursor.png"
const PLUS := DIR + "/plus.png"
## Pixels taken by each of the nine-slice's four edges (`panel.png` is made of 3×3 blocks of 32px).
const PANEL_MARGIN := 32
## Body text size = the native size of the small font. The 14 one takes too much room on 640×360; a line of text was taller than a character's head.
const TEXT_SIZE := 10
## Title size = an integer multiple of the big font (14).
const TITLE_SIZE := 28

const WHITE := Color(0.925, 0.941, 0.973)
const DIM := Color(0.471, 0.518, 0.659)
const CYAN := Color(0.471, 0.863, 0.922)
const GOLD := Color(0.961, 0.784, 0.353)
const GREEN := Color(0.549, 0.902, 0.627)
## Each stat's colour, matching the icons on the skill screen.
const STAT_COLORS := {
	&"life": Color(0.941, 0.431, 0.471),
	&"attack": Color(0.961, 0.667, 0.353),
	&"defense": Color(0.471, 0.745, 0.941),
	&"speed": Color(0.549, 0.902, 0.627),
}


## Which atlas this size uses: titles the 14 one, body text the 10 one. Both are only ever scaled by integers.
## Numbers in the UI: **past a thousand, write K**. XP and money reach five or six digits later on (a full run earns ninety thousand),
## and written out they burst the line and are tiring to read.
## Below 1000 as is; below ten thousand with one decimal (`1.2K`, no `.0` for whole numbers); above that rounded (`13K`, `154K`).
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
	var path := FONT if size >= TITLE_SIZE else FONT_SMALL
	if ResourceLoader.exists(path):
		return load(path) as Font
	return ThemeDB.fallback_font


## Load the image if the skin pack has it, otherwise null (the public build strips third-party art).
static func texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## A text control that never takes the mouse. `box` is the rectangle it takes in its parent.
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


## A window: **first fill the whole area with the middle tile, then put the nine-slice frame on top**.
## Drawing only the nine-slice leaves a ring of gap between the inner edge of the frame image and the middle tile (more visible the smaller the window).
static func window(box: Rect2) -> Control:
	if not ResourceLoader.exists(PANEL):
		# No nine-slice art: draw an outlined box, the same size and position as the nine-slice one
		var plain := UiKit.box(box, Color(0.35, 0.45, 0.7), Color(0.08, 0.1, 0.2, 0.94))
		return plain
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


## A small image (stat icons, the plus sign, the cursor). White silhouettes are tinted with tint.
## An empty `path` is a box left blank for now (to be filled with an image later, e.g. gear boxes).
static func picture(path: String, at: Vector2, tint := WHITE) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture(path)
	node.modulate = tint
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = at
	return node


## A small box (outline + fill). **Do not use `window()` for small boxes**: the nine-slice image is 96×96 with edges of 32,
## it cannot shrink below 64×64, and 30~40px boxes like portraits and gear would be blown apart into a mess.
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


## The portrait in character select: **an image ready-made in the skin pack** (`skins/<pack>/<character>/portrait.png`,
## cut by `build_portrait()` in `tools/skin_build.py` from the first idle frame of the original art).
##
## **The in-game body sprite cannot be used**: its arms have been stripped (the arms are baked separately per aim direction, see `strip_arms()`),
## so the portrait would have two empty sleeves (seen in a 2026-09 playtest). Do not put the aiming arms back either —
## that brings along a gun barrel sticking out of the box, and `strip_arms()` only strips biker cleanly;
## punk's and cyborg's arms are sleeve and armour coloured, the same colour as the torso and joined to it, so they cannot be stripped,
## and pasting arms on would give three arms. When picking a character you want to see what they look like, and the original art is the simplest and truest.
##
## **Looked up in the current skin pack's folder**, without hard-coding a pack: a DLC character's sprites may live in another pack.
## Returns null if the pack does not have the image (that box in the UI stays empty, no crash).
static func portrait(look: StringName) -> Texture2D:
	# **It has to follow the fallback chain**, not just look in the current pack's folder: each stage's pack only holds what is unique to that stage,
	# and the characters are shared by all 23 stages and only exist once, in the pack at the bottom. Looking only in the current pack,
	# all three portraits were blank on returning to the main menu after clearing stage 2 (found in playtesting).
	var path := Skins.file("%s/portrait.png" % look)
	if path.is_empty():
		path = "res://skins/cyberpunk/%s/portrait.png" % look
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Cover the whole screen with a darker layer (when paused, the stage behind is still visible but not distracting).
static func shade(alpha := 0.62) -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(0.04, 0.05, 0.11, alpha)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
