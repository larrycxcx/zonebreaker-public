class_name BossSkullAppearance
extends EnemySpriteAppearance
## The look of the basement boss, the "skull": the skull uses the base class sprites, plus **a laser drawn at the length gameplay gives**.
##
## In the art's firing frames the beam only reaches forty-odd pixels, but gameplay wants it to reach the opposite wall,
## so the beam is split into "one column" (`beam_thick` / `beam_thin`) tiled horizontally, and gameplay decides the length.
## The same approach as the arm (`BossArmAppearance`): **gameplay only calls `show_beam()` and `play()`**;
## the placeholder blocks do not have these methods, so with the default skin nothing is drawn — the rules do not change at all.
##
## Charging and firing **loop** (how long is up to gameplay, they do not just play once): charging loops the first two attack frames (`charge`),
## firing loops the last two (`beam`), with the beam flickering thick and thin.

@export var beam_thick: Texture2D
@export var beam_thin: Texture2D
## Where the laser leaves the bony hand (relative to the body origin, facing right). The same point as `BossSkull.BEAM_ORIGIN`.
@export var beam_origin_x := 20.0
## How fast the charge and firing loops run.
@export var beam_fps := 10.0

## 0 = no laser, 1 = charging, 2 = firing.
var _beam_state := 0
var _beam_length := 0.0
## Height of the beam relative to the body origin (the one gameplay locked).
var _beam_dy := 16.0


## Gameplay tells it every frame: whether the laser is on, how far it reaches and at what height.
func show_beam(state: int, length: float, dy: float) -> void:
	if state == _beam_state and is_equal_approx(length, _beam_length) and is_equal_approx(dy, _beam_dy):
		return
	var changed := state != _beam_state
	_beam_state = state
	_beam_length = length
	_beam_dy = dy
	if changed:
		_refresh()
	queue_redraw()


## When firing bone shots the base class calls this "play the firing clip once" for every shot — **the skull has no such clip** (`attack_level`),
## and going by the base class would print a "Resource file not found" per shot (found in a screenshot; stage 2's 2-C once had the same problem).
## While firing bone shots gameplay already keeps it looping the two charge frames (the bony hand glowing), so nothing needs playing here.
## Nor can the firing clip stand in: it has a stretch of level beam drawn in it, which does not match bone shots fired downward.
func fire() -> void:
	pass


## Likewise: after a diagonal bone shot the base class would think it is "aiming diagonally" and show the firing clip (missing from this pack).
## The skull has no aiming pose; it shows the same face wherever it aims.
func aim(_direction: Vector2) -> void:
	pass


## Play a one-shot clip once (summon, sneer).
func play(clip_name: StringName) -> void:
	_play_once(clip_name)


func clip() -> StringName:
	if _dead or _once != &"":
		return super()
	if _beam_state == 1:
		return &"charge"
	if _beam_state == 2:
		return &"beam"
	return super()


func _advance() -> void:
	if _beam_state != 0 and not _dead and _once == &"" and _body != null and _body.texture != null:
		_body.frame = int(_elapsed * beam_fps) % _body.hframes
		queue_redraw()
		return
	super()


func _draw() -> void:
	if _beam_state != 2 or _beam_length <= 0.0 or _dead:
		return
	# Flicker thick and thin, in step with the two firing frames of the art
	var thick := int(_elapsed * beam_fps) % 2 == 0
	var tile := beam_thick if thick or beam_thin == null else beam_thin
	if tile == null:
		return
	var h := float(tile.get_height())
	var x := beam_origin_x * _facing
	var rect := Rect2(x if _facing >= 0 else x - _beam_length, _beam_dy - h / 2.0, _beam_length, h)
	draw_texture_rect(tile, rect, true)
