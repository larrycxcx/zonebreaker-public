class_name CrateSpriteAppearance
extends Appearance
## One strip of trap sprites (barrel 1 frame, crate 8 frames). Crate: the first three frames of `Chest.png` are identical (intact),
## so "more broken the more you hit it" is done by **a shake on each hit and getting darker**; once broken the last frames (3~7, lid flying, falling apart) play once.
## Gameplay only calls `show_damage(how damaged, broken or not)`, and like other traps never touches the sprites. The barrel does not even call that; it stays on frame 0.

@export var strip: Texture2D
@export var frames := 8
@export var break_fps := 12.0
## Where the texture's top-left corner is drawn relative to the node origin (the crate's origin is its top-left corner, the barrel's the middle of its base)
@export var at := Vector2.ZERO
## How many pixels it shakes sideways when hit
const SHAKE := 1.0

var _stage := 0.0
var _broken := false
var _broken_for := 0.0


func _ready() -> void:
	pass


var _shake := 0.0


func show_damage(stage: float, broken: bool) -> void:
	if stage > _stage:
		_shake = 0.12
	_stage = stage
	_broken = broken
	modulate = Color.WHITE.lerp(Color(0.7, 0.6, 0.55), stage)
	queue_redraw()


func _process(delta: float) -> void:
	if _broken:
		_broken_for += delta
		queue_redraw()
	if _shake > 0.0:
		_shake -= delta
		position.x = SHAKE if int(_shake * 60.0) % 2 == 0 and _shake > 0.0 else 0.0


func _frame() -> int:
	if _broken:
		return mini(3 + int(_broken_for * break_fps), frames - 1)
	return mini(int(_stage * 3.0), 2)


func _draw() -> void:
	# Single-frame ones (the green zone's wooden crate) have no break-apart animation: once broken it is simply not drawn
	if strip == null or (_broken and frames < 4):
		return
	var w := strip.get_width() / float(frames)
	draw_texture_rect_region(strip, Rect2(at.x, at.y, w, strip.get_height()),
		Rect2(w * _frame(), 0.0, w, strip.get_height()))
