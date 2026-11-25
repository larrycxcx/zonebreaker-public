class_name EnemyHoverGun
extends Enemy
## Basement 4-D drone: **flies at the player's height** and fires level once lined up.
##
## Stage 1's E "follows your horizontal position and fires straight down"; this one is the reverse — **it holds its horizontal position and follows your height**.
## It guards one side of the shaft (the column it spawned in); as you climb it climbs too, and you cannot shake it, only shoot it down.
## Made for vertical stages: in a horizontal stage the player's height barely changes, so it is just a stationary turret.
##
## - No gravity (`motion_mode` = floating); it moves up and down within `leash` of its spawn point —
## without the leash it would follow the player right out of its own section and several would bunch up.
## - Its climb speed `climb_speed` is slower than the player's jump: a jump leaves it behind for a moment, and it only catches up and lines up once the player has landed.
## It only fires when lined up (body centres within `align_tolerance` in height), so that gap is the chance to dodge it.
## - It faces whichever side the player is on (it hovers in the air and can fire both ways).
## - Firing uses the base class (cooldown, bursts, muzzle = collision shape centre + `Muzzle` offset, line of sight); bullets fly level.
## - With no target in sight it hovers where it is, bobbing a little (the thrusters are firing; it must not look dead).

@export_group("Hover")
## Vertical speed while following the player's height.
@export var climb_speed := 90.0
## How far up or down it may fly from its spawn point.
@export var leash := 220.0
## It counts as lined up, and may fire, when the height difference between its body centre and the player's is within this.
@export var align_tolerance := 14.0
## Amplitude and period of the bob while hovering.
@export var bob_amplitude := 3.0
@export var bob_period := 1.2

var _home := Vector2.ZERO
var _bob_time := 0.0
## The height it is following (world coordinates, for tests).
var target_height := 0.0


func _ready() -> void:
	super()
	_home = global_position
	target_height = global_position.y


## Put it at position and use that as the centre of its vertical range.
func set_anchor(position_: Vector2) -> void:
	global_position = position_
	_home = position_
	target_height = position_.y


func _physics_process(delta: float) -> void:
	_bob_time += delta
	var target := find_target()
	if target != null:
		var side := signi(target.global_position.x - global_position.x)
		if side != 0 and side != facing:
			facing = side
			_apply_visual_facing()
		target_height = clampf((target as Player).body_center().y, _home.y - leash, _home.y + leash)
	var bob := bob_amplitude * sin(TAU * _bob_time / bob_period) if target == null else 0.0
	var goal := target_height + bob
	velocity.x = (_home.x - global_position.x) / delta
	velocity.y = clampf((goal - global_position.y) / delta, -climb_speed, climb_speed)
	move_and_slide()
	try_shoot(delta, target if target != null and is_aligned_with(target) else null)


## Is it lined up with this player: body centres within `align_tolerance` in height.
func is_aligned_with(target: Node2D) -> bool:
	var player := target as Player
	var at := player.body_center().y if player != null else target.global_position.y
	return absf(at - body_center().y) <= align_tolerance


## A player it can follow: in reach (on screen, or within detect_range in a straight line) and in sight. **Up, down, left or right alike**.
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position)) \
		and has_line_of_sight(player.body_center())


## Fire level, toward the player's side.
func shoot_direction() -> Vector2:
	return Vector2(facing, 0)
