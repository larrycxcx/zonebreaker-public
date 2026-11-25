class_name BossArmAppearance
extends EnemySpriteAppearance
## The look of the industrial zone boss, the "machine operator": the iron ball uses the base class sprites, plus a mechanical arm that **can reach any length**.
##
## The 6 `Up-Down` frames in the art only have 6 cable lengths, but how far it reaches is up to gameplay,
## so it is split into "one row of cable" tiled vertically + "the claw" at the end. The claw has an open and a closed image, switching to closed the moment it grabs.
##
## Like every appearance: **gameplay only calls `show_arm()`**; how it is drawn, how thick the cable is and what the claw looks like are this script's business.
## The placeholder blocks do not have this method, so with the default skin nothing is drawn — the rules do not change at all.

## The cable (one row, tiled vertically) and the two claw images.
@export var cable: Texture2D
@export var claw_open: Texture2D
@export var claw_shut: Texture2D
## Where on the ball the cable comes out (relative to the body origin).
@export var arm_origin := Vector2(0, 30)

## How far it reaches now (<= 0 means retracted, not drawn) and whether the claw is closed.
var _length := 0.0
var _shut := false


## Reach out length pixels; length <= 0 means retracted.
func show_arm(length: float, shut := false) -> void:
	if is_equal_approx(length, _length) and shut == _shut:
		return
	_length = length
	_shut = shut
	queue_redraw()


func _draw() -> void:
	if cable == null or _length <= 0.0:
		return
	var width := float(cable.get_width())
	var rows := roundf(_length)
	# One row of image tiled vertically (tile = true), so it never blurs however far it reaches
	draw_texture_rect(cable, Rect2(arm_origin.x - width / 2.0, arm_origin.y, width, rows), true)
	var head := claw_shut if _shut and claw_shut != null else claw_open
	if head != null:
		draw_texture(head, Vector2(arm_origin.x - head.get_width() / 2.0, arm_origin.y + rows))
