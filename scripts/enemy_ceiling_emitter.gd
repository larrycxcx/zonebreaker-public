class_name EnemyCeilingEmitter
extends Enemy
## Stage 5's 5-F: **a poison gas emitter hanging upside down from the ceiling**, never moving. When a player walks under it (within `trigger_width` left or right,
## within `trigger_depth` below, in sight) it starts: **charging first** (the attack frames play, the panels change — the warning),
## then after `charge_time` seconds **it drips a drop of poison** (`PoisonDrip`) that bursts into a poison cloud on landing (poisons you), then it rests for `cooldown` seconds.
## Dodge: hurry past when you see it charging, or shoot it down first (you have to fire up / diagonally up).
## No gravity (floating in the scene); the origin is the centre of the emitter, and the top of the mount (the ceiling) is 20 above the origin (`MOUNT`).

@export_group("Drip")
@export var drip_scene: PackedScene = preload("res://scenes/poison_drip.tscn")
@export var trigger_width := 40.0
@export var trigger_depth := 280.0
@export var charge_time := 0.6
@export var cooldown := 2.2
## Where the poison drips from (relative to the origin): under the emitter.
@export var drip_offset := Vector2(0, 14)
@export var charge_event := &"chaser_alert"

## How far above the origin the top of the mount is (for placement: the top edge touches the ceiling).
const MOUNT := 20.0

var _charge := 0.0
var _rest := 0.0


func is_charging() -> bool:
	return _charge > 0.0


func _physics_process(delta: float) -> void:
	_rest = maxf(0.0, _rest - delta)
	if _charge > 0.0:
		_charge -= delta
		if _charge <= 0.0:
			_drip()
		return
	if _rest <= 0.0 and drip_target() != null:
		_charge = charge_time
		if _visual != null:
			_visual.fire()
		GameEvents.report(charge_event, self)


## The player right below (close enough left or right, within reach below, not blocked by anything solid), or null.
func drip_target() -> Player:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) <= trigger_width and offset.y > 0.0 and offset.y <= trigger_depth \
				and has_line_of_sight(player.body_center()):
			return player
	return null


func _drip() -> void:
	_rest = cooldown
	launch_projectile(drip_scene, drip_offset, Vector2.DOWN)
