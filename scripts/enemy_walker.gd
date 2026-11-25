class_name EnemyWalker
extends Enemy
## Patrolling enemy: walks left and right, turns around at walls and platform edges, hurts the player on contact,
## and fires straight ahead (it never turns back to aim; turning is entirely up to the patrol).
## **Once a fight starts it stops walking**: when it finds a player straight ahead and starts firing back, it stands its ground
## until the player leaves its sight (or gets behind it), then resumes patrolling.
## When the player straight ahead lies prone, it stops and fires lying down; when the player stands up it stands up too and keeps patrolling.
## The ones that can fire diagonally (B, C) stop to aim and fire at a player diagonally up/down ahead, and resume patrolling once the player is level again or gone.

@export var move_speed := 60.0
@export_enum("Left:-1", "Right:1") var start_direction := -1

@onready var _floor_check: RayCast2D = $FloorCheck
@onready var _wall_check: RayCast2D = $WallCheck


func _ready() -> void:
	super()
	facing = start_direction
	_apply_facing()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	var target := _target_in_front()
	# It stands still while prone, while aiming diagonally, and **while in a firefight with the player**.
	var standing_still := is_prone or is_aiming_diagonally() or is_engaged(target)
	velocity.x = 0.0 if standing_still else walk_speed() * facing
	move_and_slide()
	_report_motion()

	if not standing_still and patrolling() and _should_turn_around():
		facing = -facing
		_apply_facing()

	var ready := update_aim(delta, target)
	# It only lies down too when the player is at about its height; when firing diagonally downward it stays standing.
	update_prone(delta, target if not is_aiming_diagonally() else null)
	try_shoot(delta, ready)


## How fast it walks toward `facing` this frame. Patrol speed by default; **subclasses that charge at the player override it** (2-D, the hammer).
func walk_speed() -> float:
	return move_speed


## Whether to turn around at ledges and walls by the patrol rules this frame. Yes by default;
## not while charging the player — at that point it faces the player, and turning would make it twitch back and forth at the cliff edge.
func patrolling() -> bool:
	return true


## Is it in a firefight with the player: once engaged it stands and fires instead of patrolling, until the player leaves its sight.
## "A player in reach straight ahead" or "a burst not yet finished" both count.
## **Ones without a gun do not count** (F's `bullet_scene` is empty); it goes by whether it can throw a grenade and overrides this itself.
func is_engaged(target: Node2D) -> bool:
	return bullet_scene != null and (target != null or is_firing_burst())


## While patrolling it should turn around when there is no ground underfoot ahead or something blocks the way.
## is_on_wall() is a necessary extra: a low ceiling blocks the upper body, which the WallCheck ray does not reach.
func _should_turn_around() -> bool:
	return is_on_floor() and (not _floor_check.is_colliding() or _wall_ahead() or is_on_wall())


## Is something blocking the way ahead. The side of a one-way platform does not count: you can pass through sideways (so can the player).
func _wall_ahead() -> bool:
	if not _wall_check.is_colliding():
		return false
	var platform := _wall_check.get_collider() as Platform
	return platform == null or not platform.one_way


## It only fires at a player straight ahead: ones behind it are out of reach and it does not turn around.
func _target_in_front() -> Node2D:
	var target := find_target()
	if target == null:
		return null
	var offset_x := target.global_position.x - global_position.x
	return target if signi(offset_x) == facing else null


func _apply_facing() -> void:
	_apply_visual_facing()
	_floor_check.position.x = absf(_floor_check.position.x) * facing
	_wall_check.target_position.x = absf(_wall_check.target_position.x) * facing
	# Recompute right after turning around, so the next frame does not use the old result and jitter back and forth.
	_floor_check.force_raycast_update()
	_wall_check.force_raycast_update()
