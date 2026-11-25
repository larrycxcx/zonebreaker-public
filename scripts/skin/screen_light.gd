class_name ScreenLight
extends ColorRect
## The skin pack's **lighting layer** (`SkinPack.lighting`): a block covering the whole view whose shader blends a coloured light map
## in overlay mode onto **what is already drawn beneath it** (that is where the pink / cyan neon of the bar street promo art comes from).
##
## **Display only**: no collision, no mouse input. The level inserts it after `Level` and before `Enemies`
## (`main.gd._add_lighting()`), so the backdrop, facades, scenery and terrain get tinted,
## while **enemies, players, bullets and effects are drawn on top in their own colours** — tinted characters would get lost in the neon.
##
## It is a node in the world, moved every frame onto what the camera sees, with `MARGIN` to spare on each side
## so no untinted strip shows at the edges when the camera moves or the screen shakes.

const MARGIN := 64.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	global_position = view.position - Vector2(MARGIN, MARGIN)
	size = view.size + Vector2(MARGIN, MARGIN) * 2.0
	var shader := material as ShaderMaterial
	if shader != null:
		shader.set_shader_parameter(&"view_origin", view.position)
