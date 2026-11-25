class_name EnemyLeaper
extends EnemyWalker
## 3-C Swordsman: a kind of patroller that **does not shoot** — when it sees the player it **winds up, leaps over, and slashes on landing**.
##
## It is the only enemy in this stage that actively crosses terrain: low walls and platforms do not stop it,
## so "hiding behind cover and chipping away" does not work on it. **The dodge is to move sideways** —
## where it lands is fixed the moment it jumps, so one step aside and the slash misses.
##
## The slash is resolved **the moment it lands** (like the hammer swing): if it could steer toward you in the air, that dodge would be pointless.

enum Leap { NONE, WINDUP, AIR, REST }

@export_group("Leap")
## It jumps within this distance (straight line, front or back — it turns around).
@export var leap_range := 170.0
## How long it winds up. The time the player gets to step aside.
@export var leap_windup := 0.35
## Jump velocity: horizontally toward the player, vertically upward.
@export var leap_speed := 170.0
@export var leap_jump := -520.0
## How long it rests after landing.
@export var leap_rest := 1.4
## The slash on landing: players within this radius get hit.
@export var slash_offset := Vector2(20, 0)
@export var slash_radius := 26.0
@export var slash_damage := 44

var _leap := Leap.NONE
var _left := 0.0
func _physics_process(delta: float) -> void:
	# **It only turns on the ground**: in the air it no longer changes facing, because its horizontal speed is `walk_speed() * facing`;
	# changing facing would make it turn back mid-air, and the "landing spot is fixed at take-off" dodge would be gone.
	if _leap == Leap.NONE or _leap == Leap.WINDUP:
		var target := leap_target()
		if target != null:
			var side := signi(target.global_position.x - global_position.x)
			if side != 0:
				facing = side
				_apply_facing()
	if _leap == Leap.AIR and is_on_floor() and velocity.y >= 0.0:
		_land()
	super(delta)
	_update_leap(delta)


func is_leaping() -> bool:
	return _leap == Leap.AIR


func is_winding_up() -> bool:
	return _leap == Leap.WINDUP


## In the air it flies in the direction fixed at take-off; it stands still while winding up and resting; otherwise it patrols as usual.
func walk_speed() -> float:
	return leap_speed if _leap == Leap.AIR else move_speed


func patrolling() -> bool:
	return _leap == Leap.NONE


func is_engaged(_target: Node2D) -> bool:
	return _leap == Leap.WINDUP or _leap == Leap.REST


func _update_leap(delta: float) -> void:
	if _leap == Leap.NONE:
		if leap_target() != null and is_on_floor():
			_leap = Leap.WINDUP
			_left = leap_windup
		return
	if _leap == Leap.AIR:
		return      # The landing is ended by `_land()`, not by the timer
	_left -= delta
	if _left > 0.0:
		return
	if _leap == Leap.WINDUP:
		_leap = Leap.AIR
		velocity.y = leap_jump
	else:
		_leap = Leap.NONE


## Landing: a sweeping slash; players within this radius get hit. **The landing spot was fixed at take-off**,
## so one step aside dodges it.
func _land() -> void:
	_leap = Leap.REST
	_left = leap_rest
	_visual.fire()
	var at := body_center() + Vector2(slash_offset.x * facing, slash_offset.y)
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= slash_radius:
			player.take_damage(roundi(slash_damage * Stage.damage_scale()), at, self)


## A player in reach and in sight (**front or back alike** — it turns around to leap).
func leap_target() -> Node2D:
	for player in players_by_distance():
		if not within_reach(global_position.distance_to(player.global_position)):
			continue
		if global_position.distance_to(player.global_position) > leap_range:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null
