class_name BossWheel
extends Boss
## Boss 3, the "wheel mech": a hulk riding a single wheel, rolling back and forth on its own ground.
##
## **Three moves in rotation** (not picked at random) — so after two rounds the player knows the rhythm, and when they die they know what went wrong:
## 1. **Cannon**: a string of straight shots at the player. Pressure at short to mid range.
## 2. **Lob**: throws a bomb into the air to drop on you (it is the enemy grenade; `Grenade` already flies in an arc, bounces once on landing, then explodes).
## **It clears cover** — this is the answer to slowly chipping away from behind a platform.
## 3. **Charge**: leans forward to wind up, then rolls over you. **That wind-up is the window for the player to jump away**.
##
## Distinct from the first two bosses: Boss A fires fans (stand in a gap), Boss 2 flies and grabs with its arm (sidestep);
## this one is **heavy ground armour** — its three moves cover "far, behind cover, in your face", so the player keeps moving.
##
## **Phase 2 below half health**: attacks faster and rolls faster, and announces it (`boss_enrage`, with sound and a screen shake).

## What it is doing now.
enum Move { ROAM, SHOOT, LOB, WINDUP, ROLL, REST }

@export_group("Movement")
## Its ground: so many pixels left and right of the spawn point. **It does not chase out** — positioning is the player's job.
@export var roam_range := 220.0
@export var roam_speed := 70.0
@export var turn_time_min := 1.0
@export var turn_time_max := 2.2

@export_group("Attacks")
## Rest between two moves.
@export var attack_rest := 1.1
## Cannon: only fires within range.
@export var shoot_range := 520.0

@export_group("Lob")
## The projectile for the lob (the enemy grenade). Leave empty to never lob.
@export var bomb_scene: PackedScene
## Release point (relative to the body centre, facing right; x flipped when facing left) — where the raised arm is.
@export var lob_offset := Vector2(6, -34)
## Time from raising the arm to letting go. The red trail in the art is the warning for this.
@export var lob_windup := 0.35
## Only worth lobbing at a player within this horizontal distance (too close blows itself up, too far falls short).
@export var lob_min := 80.0
@export var lob_max := 420.0

@export_group("Roll")
## How long it leans forward to wind up. **This is the time the player gets to jump away.**
@export var roll_windup := 0.5
@export var roll_speed := 260.0
@export var roll_time := 0.9

@export_group("Enraged")
## Below this share of health it enters phase 2.
@export_range(0.0, 1.0) var enrage_below := 0.5
## Phase 2 "attacks faster" multiplier: rest and wind-up times are multiplied by it, rolling speed is divided by it.
@export var enrage_rush := 0.7

## Cannon muzzle (relative to the body centre, facing right).
const CANNON := Vector2(36, -2)

var _move := Move.ROAM
var _left := 0.0
## Which move is next (0 cannon / 1 lob / 2 charge).
var _turn := 0
var _enraged := false

var _home := Vector2.ZERO
var _heading := 0
var _turn_left := 0.0


func _ready() -> void:
	super()
	_home = global_position
	_heading = -1
	_pick_heading()


func _boss_process(delta: float) -> void:
	_apply_gravity(delta)
	var target := find_target()
	match _move:
		Move.ROAM:
			_drift(delta)
			_left -= delta
			if _left <= 0.0 and target != null:
				_begin(target)
		Move.SHOOT:
			velocity.x = 0.0
			try_shoot(delta, target)
			if not is_firing_burst() and _fire_timer > 0.0:
				_rest()
		Move.LOB:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_release()
				_rest()
		Move.WINDUP:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_move = Move.ROLL
				_left = roll_time
				_report_motion(true)
		Move.ROLL:
			velocity.x = _speed(roll_speed) * facing
			_left -= delta
			if _left <= 0.0 or is_on_wall():
				_rest()
		Move.REST:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_move = Move.ROAM
				_left = 0.0
	move_and_slide()
	_report_motion(_move == Move.ROLL)


func move_kind() -> Move:
	return _move


func is_enraged() -> bool:
	return _enraged


## Below half health it switches gear. **The check is "at or below" and runs on every hit**:
## one grenade can take it from above half straight to below half; with "equal to", nearly every way of fighting would skip right past it.
## **Announce it** (sound + screen shake), otherwise the player never knows it changed. Reported only once.
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= float(max_health) * enrage_below:
		_enraged = true
		GameEvents.report(&"boss_enrage", self)


## Phase 2 rests less and winds up less.
func _timing(seconds: float) -> float:
	return seconds * enrage_rush if _enraged else seconds


## Phase 2 rolls faster.
func _speed(value: float) -> float:
	return value / enrage_rush if _enraged else value


## Move on to the next move. If a move cannot reach, skip it instead of waiting around.
func _begin(target: Node2D) -> void:
	# **Zero the velocity first**: `_drift()` already set a velocity this frame; without clearing it the `move_and_slide()` below
	# would carry the wandering speed for one frame — the start of the move would look like a twitch.
	velocity.x = 0.0
	for i in 3:
		var pick: int = (_turn + i) % 3
		match pick:
			0:
				if absf(target.global_position.x - global_position.x) <= shoot_range:
					_face(target)
					_move = Move.SHOOT
					_fire_timer = 0.0
					_turn = pick + 1
					return
			1:
				var gap := absf(target.global_position.x - global_position.x)
				if bomb_scene != null and gap >= lob_min and gap <= lob_max:
					_face(target)
					_move = Move.LOB
					_left = _timing(lob_windup)
					_visual.aim(Vector2(facing, -1))
					_visual.fire()
					_turn = pick + 1
					return
			2:
				_face(target)
				_move = Move.WINDUP
				_left = _timing(roll_windup)
				_turn = pick + 1
				return
	_left = attack_rest


func _rest() -> void:
	_move = Move.REST
	_left = _timing(attack_rest)
	_visual.aim(Vector2(facing, 0))


func _face(target: Node2D) -> void:
	var side := signi(target.global_position.x - global_position.x)
	if side != 0 and side != facing:
		facing = side
		_apply_visual_facing()


## Throw a bomb. **Toward the player**; `Grenade.launch()` adds the upward toss itself, so it flies in an arc —
## over cover, which is exactly what stops "hiding behind a platform and chipping away".
func _release() -> void:
	if bomb_scene == null:
		return
	launch_projectile(bomb_scene, lob_offset, Vector2(facing, 0))
	GameEvents.report(&"grenade_throw", self)


## Roll back and forth inside its ground, turning around at the edges.
func _drift(delta: float) -> void:
	_turn_left -= delta
	if _turn_left <= 0.0:
		_pick_heading()
	var offset := global_position.x - _home.x
	if absf(offset) > roam_range and signi(offset) == _heading:
		_heading = -_heading
	velocity.x = roam_speed * _heading
	if _heading != facing:
		facing = _heading
		_apply_visual_facing()


func _pick_heading() -> void:
	_turn_left = randf_range(turn_time_min, turn_time_max)
	_heading = -_heading


## A string of shots all along one line, toward the player.
func shoot_direction() -> Vector2:
	var target := find_target()
	if target == null:
		return Vector2(facing, 0.0)
	return (target.call(&"body_center") - _muzzle_position()).normalized()


func _muzzle_position() -> Vector2:
	return body_center() + Vector2(CANNON.x * facing, CANNON.y)


## Fires when it can reach; the direction is worked out by `shoot_direction()`.
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if within_reach(global_position.distance_to(target.global_position)) else -1
