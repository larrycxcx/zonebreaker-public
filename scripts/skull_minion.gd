class_name SkullMinion
extends Enemy
## The little skulls summoned by the basement boss: **fly all over the screen, circle the player, swoop every now and then**.
##
## Reworked after 2026-10 playtest feedback: they used to drift slowly toward you, blocked by one-way platforms and solid blocks, and could never reach a player hiding under the boss.
## Now:
## - **Through walls** (`collision_mask` = 0 in the scene): terrain does not stop them, but **they never leave the view** (clamped back into what the camera sees every frame);
## - normally they **circle the player** (`orbit_radius`), each in its own direction with staggered phases, so they do not bunch up;
## - every `dive_every` seconds **they stop and flash red** (`windup_time`, the warning), then **swoop in a straight line**
## at where the player was at that moment (`dive_speed` 240, faster than walking), and go back to circling afterwards.
## The dodge is to step sideways when it flashes red — it swoops at that moment's position and does not turn.
## Contact hurts (contact damage goes through the player's Hurtbox), and two shots kill one.

@export_group("Orbit")
@export var orbit_radius := 90.0
## Angular speed of the circling (radians / second) and how fast it closes onto the circle.
@export var orbit_speed := 1.6
@export var approach_speed := 90.0

@export_group("Dive")
@export var dive_speed := 240.0
@export var dive_time := 0.7
@export var windup_time := 0.4
## Time between swoops (each picks at random in this range, so they do not all swoop at once).
@export var dive_every_min := 1.6
@export var dive_every_max := 2.8
## Minimum distance from the edge of the view (the whole body stays visible).
@export var screen_margin := 8.0

enum State {ORBIT, WINDUP, DIVE}

var state := State.ORBIT
var _left := 0.0
var _angle := 0.0
var _spin := 1.0
var _dive := Vector2.ZERO


func _ready() -> void:
	super()
	gravity = 0.0
	_angle = randf() * TAU
	_spin = 1.0 if randf() < 0.5 else -1.0
	_left = randf_range(dive_every_min, dive_every_max)


func _physics_process(delta: float) -> void:
	var target := find_target() as Player
	_left -= delta
	match state:
		State.ORBIT:
			if target == null:
				velocity = Vector2.ZERO
			else:
				_angle += orbit_speed * _spin * delta
				var spot := target.body_center() + Vector2.from_angle(_angle) * orbit_radius
				var to := spot - global_position
				velocity = to.limit_length(approach_speed * delta) / delta if to.length() > 0.5 else Vector2.ZERO
				if _left <= 0.0:
					state = State.WINDUP
					_left = windup_time
					velocity = Vector2.ZERO
					# Warning: a red flash (frame Hurt2 in the art has the whole skull in red)
					_visual.flash_hit()
		State.WINDUP:
			velocity = Vector2.ZERO
			if _left <= 0.0:
				state = State.DIVE
				_left = dive_time
				var aim := (target.body_center() if target != null else global_position) - global_position
				_dive = aim.normalized() if aim.length() > 1.0 else Vector2(facing, 0)
		State.DIVE:
			velocity = _dive * dive_speed
			if _left <= 0.0:
				state = State.ORBIT
				_left = randf_range(dive_every_min, dive_every_max)
	if target != null:
		var side := signi(target.global_position.x - global_position.x)
		if side != 0 and side != facing:
			facing = side
			_apply_visual_facing()
	move_and_slide()
	_stay_on_screen()
	_report_motion(state == State.DIVE)


## Clamp it back into the view: it passes through walls, and without the clamp one swoop would send it off screen to circle back unseen, so the player could not tell where it came from.
func _stay_on_screen() -> void:
	var rig := CameraRig.find(get_tree())
	if rig == null:
		return
	var view := rig.view_rect().grow(-screen_margin)
	global_position = global_position.clamp(view.position, view.end)


func is_diving() -> bool:
	return state == State.DIVE


func is_winding_up() -> bool:
	return state == State.WINDUP


## Chase on sight: on screen or within reach counts, **line of sight is ignored** (it passes through walls).
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position))
