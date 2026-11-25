class_name Appearance
extends Node2D
## The appearance layer of a character: it sits on each character's `Visual` node and is the only interface between gameplay and "what it looks like".
##
## Gameplay only calls the methods below — facing, pose, aim, hit, blink, death, recoil —
## and never touches the blocks, colours, scale or `modulate`. A new skin just provides another implementation of the same interface; gameplay does not change by a line.
## This implementation draws the placeholder blocks: squashed means prone, `modulate` shows hits and blinking, and the gun block switches with the aim direction.
##
## It only decides how things look. Hit points (muzzles, rays, hurtboxes) always sit on the character's **body**, never inside `Visual`,
## so changing the look never changes a game rule (`tests/test_visuals.gd` guards this).

## What the character is doing right now. Gameplay works it out every frame and tells the appearance, which picks an animation (the placeholder block has only one look).
## Prone is not in here: it is expressed by `pose()`'s height ratio — one fact is stated in one place only.
enum Motion {
	IDLE,  ## Standing still
	WALK,  ## Walking
	RUN,   ## Running (holding Alt)
	JUMP,  ## Rising in the air
	FALL,  ## Falling in the air
	CLIMB, ## Climbing a ladder (player only)
	HANG,  ## Hanging on a ladder without moving (player only; same climbing clip, held on the current frame)
}

## Guns switched by aim direction (player only): direction → child node name. Ones missing from the scene are skipped.
const GUN_BY_AIM := {
	Vector2(1, 0): "Gun",
	Vector2(0, -1): "GunUp",
	Vector2(1, -1): "GunDiagonalUp",
	Vector2(1, 1): "GunDiagonalDown",
	Vector2(0, 1): "GunDown",
}

## A gun barrel that turns with the aim (enemies; the player switches between several gun blocks instead). Empty means none.
@export var turning_gun: NodePath

## Horizontal position of each child when facing right; mirrored from this when flipping (see VisualFlip).
var _bases := {}
## The offset from the pose (prone) and the temporary recoil offset are **kept separately** and added,
## otherwise shooting and lying down would wipe out each other's offset.
var _pose_offset := Vector2.ZERO
var _kick := Vector2.ZERO
var _facing := 1
var _aim := Vector2.RIGHT


func _ready() -> void:
	_bases = VisualFlip.capture(self)
	face(_facing)


## Facing: 1 is right, -1 is left.
func face(facing: int) -> void:
	_facing = facing
	VisualFlip.apply(_bases, facing)
	_turn_gun()


## Aim direction (unit vector): switch the gun block to match and turn the turning barrel.
func aim(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_aim = direction
	var key := Vector2(absf(signf(_aim.x)), signf(_aim.y))
	for aim_key in GUN_BY_AIM:
		var gun := get_node_or_null(NodePath(GUN_BY_AIM[aim_key])) as CanvasItem
		if gun != null:
			gun.visible = aim_key == key
	_turn_gun()


## Which gun is being held (`Weapon.look`). The placeholder has one gun, nothing to do; the sprite version swaps a whole set of arm sprites.
func hold(_look: StringName) -> void:
	pass


## A shot was fired (once per bullet). Nothing for the placeholder; the sprite version plays the firing clip once.
func fire() -> void:
	pass


## What it is doing (stand / walk / run / rise / fall). The placeholder has one look, nothing to do; the sprite version picks a clip.
func motion(_state: Motion) -> void:
	pass


## Pose: the body is squashed to `height_ratio` of its height and moved down by `lowered`.
## The placeholder simply squashes vertically; with sprites this switches between the "standing" and "prone" sets.
func pose(height_ratio: float, lowered: float) -> void:
	scale.y = height_ratio
	_pose_offset.y = lowered
	_apply_offset()


## Temporary offsets such as recoil (pure presentation, affects no hit check).
func kick(offset: Vector2) -> void:
	_kick = offset
	_apply_offset()


## Status tint (2026-11, stage 5 poison): while a status is on, the whole character carries a colour so it is obvious at a glance.
## After a hit flash or a revive it **returns to this colour, not pure white** — otherwise one hit would wash the green off; invincibility blinking only touches alpha.
## Several statuses at once multiply their colours. Statuses not in the table do not tint.
const STATUS_TINTS := {&"poison": Color(0.62, 1.0, 0.5)}

var _statuses := {}
var _tint := Color.WHITE


## A status was applied / removed (the player forwards `StatusEffects.changed`).
func show_status(id: StringName, active: bool) -> void:
	if active:
		_statuses[id] = true
	else:
		_statuses.erase(id)
	_tint = Color.WHITE
	for key: StringName in _statuses:
		_tint *= STATUS_TINTS.get(key, Color.WHITE)
	modulate = Color(_tint.r, _tint.g, _tint.b, modulate.a)


## Buried underground (stage 5's 5-E): the placeholder is drawn half transparent — even the public build without art shows "something is buried here";
## the pack's appearance holds the first frame of the "emerge" clip (just a tread on the floor). `emerge()` is the moment it comes out.
func show_buried(buried: bool) -> void:
	modulate.a = 0.3 if buried else 1.0


func emerge() -> void:
	modulate.a = 1.0


## Current status tint (pure white = none).
func status_tint() -> Color:
	return _tint


## Got hit: flash white.
func flash_hit() -> void:
	modulate = Color(2.0, 2.0, 2.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(_tint.r, _tint.g, _tint.b, 1.0), 0.12)


## Invincibility blink: 1.0 is normal, below 1 is the faded beat.
func blink(alpha: float) -> void:
	modulate.a = alpha


## Dead: darken everything.
func show_dead() -> void:
	modulate = Color(0.5, 0.5, 0.5, 1.0)


## Back on its feet (revived by the partner in co-op). The opposite of `show_dead()`; enemies never use it (they are deleted when they die).
func revive() -> void:
	modulate = _tint


func _apply_offset() -> void:
	position = _pose_offset + _kick


func _turn_gun() -> void:
	var gun := get_node_or_null(turning_gun) as Control
	if gun != null:
		VisualFlip.aim_gun(gun, _facing, _aim)
