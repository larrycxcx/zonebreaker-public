class_name BossMissile
extends Boss
## Boss A: a four-legged missile mech. Big, jumps, never goes prone, fires fans from the missile pod on its back; it does not chase,
## but touching the player still deals contact damage (base class rule).
##
## - Movement: inside its ground (±roam_range around the spawn point) it "looks for a firing spot", steered by **its horizontal distance to the player**:
## too close (< close_range) it backs off while firing, too far (> far_range) it closes into range, in between it wanders randomly.
## **It never leaves its ground**, so it does not chase the player like enemy D (chasing is D's job; this one shoots).
## It also jumps every random while.
## - Range 680 (straight line): once it appears it can reach the player anywhere on screen (the screen is 640 wide).
## - Shooting: a **missile fan**. The pod fires fan_count missiles at once, centred on the direction "pod mouth → player body centre",
## fan_spread degrees apart. The pod only faces forward: the fan centre deviates at most fan_max_angle from level, so it cannot hit straight up or behind.
## It aims at the body centre; a prone player's centre is lower and the fan follows it down, so **lying prone does not dodge it** — stand in a gap or jump away.
## It only fires with its feet on the ground (in the air it is doing the jet jump), and keeps firing while walking.
## (The art only has a forward-facing pod, no turning barrel, so there is no 8-way single shot; the old "jump onto the high ground when the player is prone" behaviour went too —
## the fan reaches prone players anyway. The platform in the boss area is still there, just ordinary terrain.)
## - Dodging grenades: when a grenade that has already landed (Grenade.landed) and is bouncing along the floor comes within dodge_distance, it jumps and moves away from it;
## grenades still in flight that never landed are not dodged (they can hit it directly).

@export_group("Movement")
## Walking speed, and the radius of its ground (centred on the spawn point; it turns back at the edge and never chases out).
@export var roam_speed := 90.0
@export var roam_range := 160.0
## Within this distance of the player it backs off (firing as it goes); beyond far_range it closes in; in between it wanders.
@export var close_range := 100.0
@export var far_range := 280.0
## Speed while backing off. Slower than the player's walk (90), so the player can always close in — at the cost of its close-range fire.
@export var back_off_speed := 120.0
## How often it picks a new random walking direction (seconds, between these two values).
@export var turn_time_min := 1.0
@export var turn_time_max := 2.5
@export var jump_velocity := -640.0
## Time between jumps (seconds, between these two values).
@export var jump_interval_min := 1.5
@export var jump_interval_max := 3.0

@export_group("Missile fan")
## Missiles per fan and degrees between neighbours.
@export var fan_count := 5
@export var fan_spread := 20.0
## How far the fan centre may deviate from level (the pod faces forward and never fires straight up, down or behind).
@export var fan_max_angle := 60.0

@export_group("Grenade dodge")
## How close (horizontally) a landed grenade gets before it dodges. Grenade blast radius 28 + half its body width, plus some margin.
@export var dodge_distance := 112.0
## Horizontal speed while dodging.
@export var dodge_speed := 220.0

## Pod mouth (relative to the body centre, facing right; x flipped when facing left): on top of the hull, where the missiles leave in the art.
const POD_MUZZLE := Vector2(4, -22)

## Direction of the centre of the latest fan (read by tests).
var fan_center := Vector2.LEFT
## Whether it is dodging a grenade this frame (read by tests).
var is_dodging := false

var _home := Vector2.ZERO
var _roam_dir := -1
var _turn_timer := 0.0
var _jump_timer := 0.0

func _ready() -> void:
	super()
	_home = global_position
	_turn_timer = randf_range(turn_time_min, turn_time_max)
	_jump_timer = randf_range(jump_interval_min, jump_interval_max)


func _boss_process(delta: float) -> void:
	_apply_gravity(delta)
	var threat := _grenade_threat()
	is_dodging = threat != null
	var target := find_target()
	# Priority: dodging grenades > normal walking.
	if is_dodging:
		_dodge(threat)
	else:
		_reposition(delta, target)
	move_and_slide()
	_report_motion()
	if is_on_wall():
		_roam_dir = -_roam_dir

	# The pod faces forward: turn toward the target if there is one, otherwise toward the walking direction
	var turn_to := signf(target.global_position.x - global_position.x) if target != null else signf(velocity.x)
	if turn_to != 0.0 and int(turn_to) != facing:
		facing = int(turn_to)
		_apply_visual_facing()
	_fire_timer -= delta
	if target != null and is_on_floor() and _fire_timer <= 0.0:
		_fire_timer = fire_interval
		fire_fan(target)


## Fire one fan: centred on the direction from the pod mouth to the target's body centre (clamped to ±fan_max_angle from forward), fan_spread degrees apart.
func fire_fan(target: Node2D) -> void:
	var point: Vector2 = target.body_center() if target is Player else target.global_position
	var offset := point - _muzzle_position()
	# Measure the elevation with "level forward" as 0 degrees; flip x when facing left, then flip back at the end
	var pitch := clampf(atan2(offset.y, absf(offset.x)), -deg_to_rad(fan_max_angle), deg_to_rad(fan_max_angle))
	fan_center = Vector2(cos(pitch) * facing, sin(pitch))
	for i in fan_count:
		var angle := pitch + deg_to_rad(fan_spread) * (i - (fan_count - 1) / 2.0)
		_burst_direction = Vector2(cos(angle) * facing, sin(angle))
		_fire_one()


## Find a firing spot by distance to the player: back off when too close, close in when too far, wander in between; turn back at the edge of its ground.
func _reposition(delta: float, target: Node2D) -> void:
	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_roam_dir = -_roam_dir
		_turn_timer = randf_range(turn_time_min, turn_time_max)
	var speed := roam_speed
	var dir := float(_roam_dir)
	if target != null:
		var offset := target.global_position.x - global_position.x
		var toward := signf(offset)
		if toward == 0.0:
			toward = float(facing)
		if absf(offset) < close_range:
			dir = -toward
			speed = back_off_speed
		elif absf(offset) > far_range:
			dir = toward
	# The edge of its ground beats every rule above: better to let the player get in its face than to chase out.
	if global_position.x > _home.x + roam_range:
		dir = -1.0
		speed = roam_speed
	elif global_position.x < _home.x - roam_range:
		dir = 1.0
		speed = roam_speed
	_roam_dir = signi(dir)
	velocity.x = speed * dir
	if is_on_floor():
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			velocity.y = jump_velocity
			_jump_timer = randf_range(jump_interval_min, jump_interval_max)


## Jump and move away from the grenade (when a wall blocks the retreat, the jump alone still lifts it out of the blast).
func _dodge(grenade: Grenade) -> void:
	var away := signf(global_position.x - grenade.global_position.x)
	if away == 0.0:
		away = -facing
	velocity.x = dodge_speed * away
	if is_on_floor():
		velocity.y = jump_velocity


## The nearest grenade that has landed (within dodge_distance), or null. Grenades still in the air do not count.
func _grenade_threat() -> Grenade:
	var nearest: Grenade = null
	var best := dodge_distance
	for node in get_tree().get_nodes_in_group(Grenade.GROUP):
		var grenade := node as Grenade
		if grenade == null or not grenade.landed or grenade.exploded:
			continue
		var distance := absf(grenade.global_position.x - global_position.x)
		if distance <= best:
			best = distance
			nearest = grenade
	return nearest


## Fires when the target is in range (straight-line distance) and visible; fire_fan works out the fan direction.
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if within_reach(global_position.distance_to(target.global_position)) else -1


## The look is always the forward-facing pod (no turning barrel).
func shoot_direction() -> Vector2:
	return Vector2(facing, 0)


func _muzzle_position() -> Vector2:
	return global_position + Vector2(POD_MUZZLE.x * facing, POD_MUZZLE.y)
