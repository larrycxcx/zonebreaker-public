class_name BossOperator
extends Boss
## Boss 2, the "machine operator": an iron ball floating in the air that can lower a mechanical arm.
##
## **It alternates two attacks** (the big difference from Boss A, which only fires fans):
## 1. **Arm**: with someone right below, the cable drops; the claw closes at the bottom and grabs whoever is there.
## Lowering takes time and the claw only covers a small patch straight below, so **running away dodges it** — the same idea as the hammer man.
## 2. **Bullets**: with the arm retracted it fires a burst from the hatch under the ball, **all along the same line** ("one way"),
## not a fan like Boss A. The dodge differs too: that one means standing in a gap, this one means sidestepping.
##
## It flies without gravity (`motion_mode` floating in the scene), drifting in eight directions inside a rectangle around its spawn point.
## **It never leaves its ground**: chasing is enemy D's job; this one presses from above, and the player has to jump up on platforms to hit it.

@export_group("Movement")
## Its ground: so many pixels each way horizontally and vertically around the spawn point.
@export var roam_range := Vector2(200.0, 88.0)
@export var roam_speed := 70.0
## How often it changes direction.
@export var turn_time_min := 0.8
@export var turn_time_max := 1.8

@export_group("Arm")
## Longest cable length (measured from the bottom of the ball).
@export var arm_max_length := 132.0
## Speed of lowering and raising.
@export var arm_speed := 320.0
## How long the claw takes to close and grab.
@export var arm_grab_time := 0.25
## The player counts as "right below" (worth lowering the arm for) within this horizontal distance.
@export var arm_width := 36.0
## Players within this radius of the claw get grabbed.
@export var claw_radius := 22.0
@export var claw_damage := 46

@export_group("Volley")
## Rest between two attacks.
@export var attack_interval := 1.2

@export_group("Enraged")
## Below this share of health it enters phase 2: flies faster and the single line of bullets becomes a fan.
## **Phase 1 only fires one line, which you dodge by stepping aside** — if it never changed after half health, the second half would be a slog (playtest feedback).
@export_range(0.0, 1.0) var enrage_below := 0.5
## Flying speed multiplier in phase 2.
@export var enrage_speed_scale := 1.5
## In phase 2 one shot becomes this many, this many degrees apart.
@export var enrage_fan_count := 3
@export var enrage_fan_spread := 18.0
## Phase 2 "attacks faster" multiplier: the fire interval and the pause between attacks are multiplied by it, cable speed is divided by it.
## **The arm has to speed up too** — the player usually stands right below it, where it keeps using the arm;
## changing only the flying speed and the bullet fan would make phase 2 invisible from the most common spot (2026-09 playtest feedback).
@export var enrage_rush := 0.7

## Where the cable leaves the ball and where bullets come out (relative to the body origin). Both are the same hatch.
const POD_MUZZLE := Vector2(0, 30)

## The four states of the arm: retracted / lowering / claw closing to grab / raising.
enum Arm {IN, OUT, GRAB, BACK}

var _arm := Arm.IN
var _arm_length := 0.0
## How far to lower this time: **stop at the player's height**, not always to full length.
## Lowering to full length every time would send the claw right past the head of anyone standing a little higher.
var _arm_goal := 0.0
var _grab_left := 0.0
## Whether the arm or the bullets go next.
var _arm_next := true
## Firing a round of bullets right now (used to tell when the round is over).
var _volleying := false
var _rest := 0.0
## How many shots of this phase-2 round have gone out (used to spread the fan).
var _fan_index := 0
## Whether it is in phase 2. **A latch**, not recomputed from health every frame — the switch happens once, which is what lets it be announced.
var _enraged := false

var _home := Vector2.ZERO
var _heading := Vector2.ZERO
var _turn_left := 0.0


func _ready() -> void:
	super()
	_home = global_position
	_pick_heading()


func _boss_process(delta: float) -> void:
	# **It does not drift while the arm is out**: the cable hangs, so drifting while lowering would land the claw away from where it aimed,
	# and a player who never moved could be missed (or one standing still could be grabbed). Holding still also makes the attack readable and dodgeable.
	if _arm == Arm.IN:
		_drift(delta)
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_report_motion()
	if _arm != Arm.IN:
		_update_arm(delta)
		return
	_rest -= delta
	var target := find_target()
	if target == null or _rest > 0.0:
		return
	var below := arm_target()
	if _arm_next and below != null:
		_arm = Arm.OUT
		_arm_goal = clampf(below.call(&"body_center").y - global_position.y - POD_MUZZLE.y,
			0.0, arm_max_length)
		_arm_next = false
		return
	# Nobody right below: do not wait around, fire bullets instead (the arm still goes first next round)
	try_shoot(delta, target)
	if is_firing_burst():
		_volleying = true
	elif _volleying:
		_volleying = false
		_arm_next = true
		_rest = attack_interval


func arm_length() -> float:
	return _arm_length


func arm_state() -> Arm:
	return _arm


## A player right below (within arm_width horizontally), underneath and within reach; otherwise null.
func arm_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) > arm_width or offset.y <= 0.0:
			continue
		if offset.y - POD_MUZZLE.y > arm_max_length:
			continue
		return player
	return null


## Where the claw is now (world coordinates).
func claw_position() -> Vector2:
	return global_position + POD_MUZZLE + Vector2(0.0, _arm_length)


func _update_arm(delta: float) -> void:
	match _arm:
		Arm.OUT:
			_arm_length = minf(_arm_length + arm_speed * delta, _arm_goal)
			if is_equal_approx(_arm_length, _arm_goal):
				_arm = Arm.GRAB
				_grab_left = arm_grab_time
				_snap_shut()
		Arm.GRAB:
			_grab_left -= delta
			if _grab_left <= 0.0:
				_arm = Arm.BACK
		Arm.BACK:
			_arm_length = maxf(_arm_length - arm_speed * delta, 0.0)
			if _arm_length <= 0.0:
				_arm = Arm.IN
				_rest = attack_interval
	_show_arm()


## Damage only lands at the moment the claw reaches the bottom and closes: lowering takes time, during which the player can see it and get away.
func _snap_shut() -> void:
	var at := claw_position()
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= claw_radius:
			player.take_damage(roundi(claw_damage * Stage.damage_scale()), at, self)


func _show_arm() -> void:
	if _visual.has_method(&"show_arm"):
		_visual.call(&"show_arm", _arm_length, _arm == Arm.GRAB)


## Drift in eight directions inside its ground; when it hits an edge, flip that component.
func _drift(delta: float) -> void:
	_turn_left -= delta
	if _turn_left <= 0.0:
		_pick_heading()
	var offset := global_position - _home
	if absf(offset.x) > roam_range.x and signf(offset.x) == signf(_heading.x):
		_heading.x = -_heading.x
	if absf(offset.y) > roam_range.y and signf(offset.y) == signf(_heading.y):
		_heading.y = -_heading.y
	velocity = _heading * roam_speed * (enrage_speed_scale if is_enraged() else 1.0)
	if not is_zero_approx(_heading.x):
		facing = signi(_heading.x)
		_apply_visual_facing()


## Pick one of the eight directions at random (never standing still).
func _pick_heading() -> void:
	_turn_left = randf_range(turn_time_min, turn_time_max)
	var pick := randi_range(0, 7)
	var angle := pick * TAU / 8.0
	_heading = Vector2(snappedf(cos(angle), 0.001), snappedf(sin(angle), 0.001)).normalized()


## Whether it is in phase 2.
func is_enraged() -> bool:
	return _enraged


## Below half health it switches gear and **reports an event** (sound + a screen shake) —
## without it the player never notices the change: flying a little faster and two extra bullets are not visible enough (2026-09 playtest feedback).
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= float(max_health) * enrage_below:
		_enraged = true
		fire_interval *= enrage_rush
		attack_interval *= enrage_rush
		arm_speed /= enrage_rush
		GameEvents.report(&"boss_enrage", self)


## All bullets of a round go along one line ("one way"): the base class calls this once at the start of a round to lock the direction, the rest reuse it.
## **The fan counter is reset here as well** — this is only called once per round, exactly when "a round starts".
func shoot_direction() -> Vector2:
	_fan_index = 0
	var target := find_target()
	if target == null:
		return Vector2(facing, 0.0)
	return (target.call(&"body_center") - _muzzle_position()).normalized()


## Which way this shot flies. In phase 1 it is the locked line; **in phase 2 each shot is offset a little**,
## so a round makes a fan and the dodge changes from "sidestep" to "stand in the gap between two shots".
func burst_direction() -> Vector2:
	if not is_enraged():
		return super()
	var middle := (enrage_fan_count - 1) / 2.0
	var step: float = (_fan_index % enrage_fan_count) - middle
	_fan_index += 1
	return super().rotated(deg_to_rad(step * enrage_fan_spread))


## Bullets and cable leave from the same hatch.
func _muzzle_position() -> Vector2:
	return global_position + POD_MUZZLE


## It makes no level / diagonal distinction: if it can reach, it fires, with the direction worked out by `shoot_direction()`.
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if within_reach(global_position.distance_to(target.global_position)) else -1
