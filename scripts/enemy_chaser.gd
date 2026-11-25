class_name EnemyChaser
extends EnemyWalker
## Enemy D: does not shoot or go prone, hurts only by contact, has as much health as the turret.
## Normally it walks back and forth like a patroller at normal speed (move_speed); when it sees the player within detect_range (120px) in a straight line,
## it charges at charge speed and can jump over walls and onto platforms like the player. Walls block its sight.
##
## When it loses the player (the player went over a wall, out of sight) it keeps charging to where it last saw them, jumping over obstacles,
## and gives up and goes back to patrolling if it has not seen them again within memory_time seconds. That way "walls block sight" and "it climbs walls to chase you" both hold:
## hide behind a wall from the start and it never notices you, but once it is on you, climbing a wall will not shake it off.

## Charge speed. Deliberately slower than the player's walk (90): walking away outpaces it and running opens a clear gap, so it can be shaken off.
@export var charge_speed := 150.0
## Jump strength is the same as the player's, so it clears every wall (every wall is lower than the player's jump).
@export var jump_velocity := -560.0
## After losing the player, how long it keeps chasing toward where it last saw them.
@export var memory_time := 2.0
## Minimum time between two jumps, so it does not jump on the spot under a platform it cannot reach.
@export var jump_cooldown := 0.5
## When the player is this much higher and within climb_reach horizontally, it jumps for the platform.
@export var climb_height := 40.0
@export var climb_reach := 48.0
## How fast and for how long it bounces back after bumping into the player. **Without the bounce it would stay glued to the player**,
## and as soon as the invincibility frames ran out it would hit again; a player pinned in a corner could only stand and take it.
## It bounces about 60px; by the time it charges back the invincibility frames are just about over, so the rhythm becomes "hit, back off, again".
@export var bounce_speed := 200.0
@export var bounce_time := 0.3
## Play the attack clip once on the bump (the shirtless 4-A in the basement — bumping into you is a heavy punch).
## Off by default: D and 2-B have no such clip, and turning it on would look for a sprite that does not exist.
@export var punch_on_contact := false

var is_chasing := false

var _last_seen := Vector2.ZERO
var _memory_left := 0.0
var _jump_timer := 0.0
## Which way it is walking off a platform (0 = not). With the player right below it must pick a direction and walk all the way to the edge,
## otherwise it would re-aim at the player every frame and jitter left and right above their head.
var _drop_direction := 0
## Height when it started walking to the edge. It only counts as falling once its body has actually dropped; is_on_floor() alone is not enough (it flickers at edges).
var _drop_start_y := 0.0
## Bouncing back: time left and which way. The facing does not change (still toward the player); it is just being pushed back.
var _bounce_left := 0.0
var _bounce_facing := 0


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_jump_timer -= delta

	var target := find_target()
	if target != null:
		_last_seen = target.global_position
		_memory_left = memory_time
	else:
		_memory_left -= delta
	var was_chasing := is_chasing
	is_chasing = _memory_left > 0.0
	if is_chasing and not was_chasing:
		GameEvents.report(&"chaser_alert", self)

	if _bounce_left > 0.0:
		# While bouncing it neither chases nor patrols, it just backs off; afterwards it carries on chasing
		_bounce_left -= delta
		_drop_direction = 0
		velocity.x = bounce_speed * _bounce_facing
	elif is_chasing:
		_chase(delta, target != null)
	else:
		_drop_direction = 0
		velocity.x = move_speed * facing
	move_and_slide()
	_report_motion(is_chasing)

	# While patrolling it turns around at ledges and walls like a patroller; while chasing it does not — it jumps down ledges and over walls.
	# It does not turn during the bounce either, or right after being pushed back it would turn around and look like it walked away on its own.
	if not is_chasing and _bounce_left <= 0.0 and _should_turn_around():
		facing = -facing
		_apply_facing()


## It bumped into the player: bounce away from them. **The facing stays** — it still faces the player, it was just pushed back.
func bounced_off(from: Vector2) -> void:
	if punch_on_contact:
		_visual.fire()
	_bounce_left = bounce_time
	_bounce_facing = signi(global_position.x - from.x)
	if _bounce_facing == 0:
		_bounce_facing = -facing


## Whether it is bouncing back (for tests).
func is_bouncing() -> bool:
	return _bounce_left > 0.0


## A player within straight-line distance and in sight. D jumps, so it must also notice a player on a platform overhead; hence no "horizontal range + height difference" check.
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position)) and has_line_of_sight(player.body_center())


func _chase(delta: float, can_see: bool) -> void:
	var offset := _last_seen - global_position
	# It stands up high with the player right below: pick the current facing and walk off the edge of the platform.
	# One-way platforms do not block sight; without this it would stand above the player forever, "can see, cannot reach".
	# Only cancelled once its body has really dropped (2px or more below where it started walking) or it is at the player's height; once cancelled it never resumes.
	# It cannot be cancelled on "left the floor": at the edge is_on_floor() flickers false for a frame, it would step back onto the platform, turn and walk back, running back and forth on the platform.
	# When it lands somewhere still higher than the player (say a wall top), the condition below picks a direction again.
	if _drop_direction != 0 and (offset.y <= climb_height or global_position.y > _drop_start_y + 4.0):
		_drop_direction = 0
	elif _drop_direction == 0 and is_on_floor() and offset.y > climb_height and absf(offset.x) < climb_reach:
		_drop_direction = facing
		_drop_start_y = global_position.y

	# The chosen direction is only for walking to the edge; once it starts falling (cancelled above) it steers toward the player in the air as usual,
	# otherwise it would fly off at charge speed, maybe even over a low wall to the other side.
	if _drop_direction != 0:
		# If this side is blocked by a wall, go down the other side.
		if is_on_wall():
			_drop_direction = -_drop_direction
		if facing != _drop_direction:
			facing = _drop_direction
			_apply_facing()
		velocity.x = charge_speed * _drop_direction
		return

	# The threshold is the distance it can cover this frame: a fixed small threshold makes a fast mover overshoot back and forth around the target.
	if absf(offset.x) > charge_speed * delta:
		var direction := signi(offset.x)
		if direction != facing:
			facing = direction
			_apply_facing()
		velocity.x = charge_speed * facing
	else:
		velocity.x = 0.0
		# It reached where it last saw the player and still cannot see them: it has lost them.
		if not can_see:
			_memory_left = 0.0

	if not is_on_floor() or _jump_timer > 0.0:
		return
	var blocked := is_on_wall() or _wall_ahead()
	var target_above := -offset.y > climb_height and absf(offset.x) < climb_reach
	if blocked or target_above:
		velocity.y = jump_velocity
		_jump_timer = jump_cooldown
