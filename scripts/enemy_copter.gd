class_name EnemyCopter
extends EnemyFlyer
## 2-E Copter: the flying one, but it **does not shoot; it drops bombs** — the ready-made grenade, like F.
##
## Flying, patrolling and following all come from `EnemyFlyer`; `bullet_scene` is empty, so the base class shooting never fires.
## The bomb is the enemy grenade (`enemy_grenade.tscn`): released straight down with no upward toss, so it falls straight,
## bounces once on landing and explodes on the next touch, exactly the same rules as the player's grenade.
##
## **The bomb lets go on frame 3 of the clip** (`RELEASE_FRAME`), not the moment the attack starts: those two frames in the art are the hull dipping and the hook opening,
## and the bomb leaves the belly right where it should.

@export_group("Bombs")
## Leave empty to never drop anything (then it just flies around).
@export var bomb_scene: PackedScene
## Minimum time between two bombs.
@export var drop_interval := 2.0
## Release point (relative to the body centre; x flipped when facing left, though it drops from right under the belly and x is 0 anyway).
@export var bomb_offset := Vector2(0, 10)
@export var drop_event := &"grenade_throw"

## The frame of the clip on which it lets go, and how many frames per second one-shot clips run (**must match `EnemySpriteAppearance.ONCE_FPS`**).
const RELEASE_FRAME := 2
const RELEASE_FPS := 12.0
const RELEASE_DELAY := RELEASE_FRAME / RELEASE_FPS

var _drop_timer := 0.0
## Time left until release after starting the drop; <= 0 means not dropping.
var _release_left := 0.0


func _physics_process(delta: float) -> void:
	super(delta)
	_update_drop(delta)


func _update_drop(delta: float) -> void:
	_drop_timer -= delta
	if _release_left > 0.0:
		_release_left -= delta
		if _release_left <= 0.0:
			_release()
		return
	if bomb_scene == null or _drop_timer > 0.0 or drop_target() == null:
		return
	_drop_timer = drop_interval
	_release_left = RELEASE_DELAY
	_visual.fire()


## A player right below (within below_width horizontally) and in sight; otherwise null. Same check as the base class firing.
func drop_target() -> Node2D:
	var target := find_target()
	if target == null or absf(target.global_position.x - global_position.x) > below_width:
		return null
	return target


func _release() -> void:
	launch_projectile(bomb_scene, bomb_offset, Vector2.DOWN)
	GameEvents.report(drop_event, self)
