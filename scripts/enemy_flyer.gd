class_name EnemyFlyer
extends Enemy
## Enemy E: flies, no gravity. Patrols back and forth along a wave near a fixed height, at the same horizontal speed as ordinary enemies.
## When it sees a player below (within follow_range horizontally, or it is on screen itself; and in sight) it starts following: moving horizontally above the player,
## and fires straight down when the player is **directly below** it (within below_width horizontally).
## "On screen counts as seeing" is for fairness: when the player can see it, it has to react, not be shot for free from the screen. Its bullets pass through one-way platforms like any other and are stopped by solid things like the ground, walls and crawl passages.
## While following, if it loses sight of the player or the player moves beyond follow_range horizontally, it gives up after memory_time seconds and patrols where it is.

@export var move_speed := 60.0
## Horizontal speed while following the player.
@export var follow_speed := 60.0
@export_enum("Left:-1", "Right:1") var start_direction := -1
## Patrol range: so many pixels left and right of the patrol centre.
@export var patrol_distance := 180.0
## Amplitude (pixels) and period (seconds) of the wave.
@export var wave_amplitude := 16.0
@export var wave_period := 2.0
## A player within this horizontal distance counts as "directly below" it.
@export var below_width := 20.0
## How far the player must move away horizontally while being followed to count as lost.
@export var follow_range := 280.0
@export var memory_time := 1.5

var is_following := false

## The height the wave runs around and the patrol centre. Taken from the position at spawn; set_anchor() can change it.
var _base_y := 0.0
var _patrol_center_x := 0.0
var _wave_time := 0.0
var _memory_left := 0.0


func _ready() -> void:
	super()
	facing = start_direction
	_apply_visual_facing()
	set_anchor(global_position)


## Put it at position and use that as the wave height and patrol centre.
func set_anchor(position_: Vector2) -> void:
	global_position = position_
	_base_y = position_.y
	_patrol_center_x = position_.x
	_wave_time = 0.0


func _physics_process(delta: float) -> void:
	_wave_time += delta
	var target := find_target()
	var below := target != null and absf(target.global_position.x - global_position.x) <= below_width

	if target != null:
		is_following = true
	if is_following:
		if target != null:
			_memory_left = memory_time
			_follow(delta, target)
		else:
			velocity.x = 0.0
			_memory_left -= delta
			if _memory_left <= 0.0:
				# Lost the player: patrol around where it is now instead of flying back to its spawn point.
				is_following = false
				_patrol_center_x = global_position.x
	else:
		velocity.x = move_speed * facing

	# Wave: every frame pull the height toward the target on the sine curve.
	var wave_y := _base_y + wave_amplitude * sin(TAU * _wave_time / wave_period)
	velocity.y = (wave_y - global_position.y) / delta
	move_and_slide()

	if not is_following and _should_turn_around():
		_set_facing(-facing)

	try_shoot(delta, target if below else null)


## A player it can follow: below it, within reach horizontally (inside follow_range, or it is on screen itself), and in sight (looking down from the muzzle).
func can_target(player: Player) -> bool:
	var offset := player.global_position - global_position
	if offset.y <= 0.0 or (absf(offset.x) > follow_range and not is_partly_on_screen()):
		return false
	return has_line_of_sight(player.body_center())


func shoot_direction() -> Vector2:
	return Vector2.DOWN


func _follow(delta: float, target: Node2D) -> void:
	var offset_x := target.global_position.x - global_position.x
	if absf(offset_x) > follow_speed * delta:
		_set_facing(signi(offset_x))
		velocity.x = follow_speed * facing
	else:
		velocity.x = 0.0


## Turn around at the edge of the patrol range or on hitting a wall.
func _should_turn_around() -> bool:
	var past_edge := (global_position.x - _patrol_center_x) * facing >= patrol_distance
	return past_edge or is_on_wall()


func _set_facing(value: int) -> void:
	if value == facing:
		return
	facing = value
	_apply_visual_facing()
