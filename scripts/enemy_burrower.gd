class_name EnemyBurrower
extends EnemyChaser
## Stage 5's 5-E: **a spider claw arm buried in the ground** (claw-arm head + spider legs). Agreed with the user in 2026-11:
## - **Buried**: only a tread shows on the floor (the pack's appearance; the placeholder is drawn half transparent) — that is the warning. While buried its collision layer is cleared:
## it cannot be shot or bumped, and the ultimate cannot reach it either.
## - When a player comes near (within `trigger_range` left or right, on about the same layer) → it **emerges**: the tread slides aside and the mech rises (`emerge_time`),
## and collisions come back once it is out.
## - Once out it **chases** like D (the spider legs can walk, jump onto platforms and climb walls).
## - Within `spin_range` → it stops and **spins in place** (`spin_time`): the claw sweep frames play while it flips left and right quickly,
## and halfway through **it hits both sides** (anyone within `spin_radius`). After the spin it **rests a moment** (`rest_time`) — the chance to hit back.

enum State { BURIED, EMERGING, HUNTING, SPINNING, RESTING }

@export_group("Burrow")
@export var trigger_range := 110.0
## Only within this height difference does a player count as "on the same layer" (otherwise walking past upstairs would bring it out).
@export var trigger_height := 48.0
@export var emerge_time := 0.7
@export var emerge_event := &"chaser_alert"

@export_group("Spin")
@export var spin_range := 40.0
@export var spin_time := 0.8
## When in the spin it hits (the claw is sweeping past at that point).
@export var spin_hit_at := 0.4
@export var spin_radius := 46.0
@export var spin_damage := 48
## How often it flips around (flipping left and right fast = spinning).
@export var spin_flip := 0.1
@export var rest_time := 0.7

var state := State.BURIED
var _left := 0.0
var _flip_left := 0.0
var _spun := false
var _layer := 8


func _ready() -> void:
	super()
	_layer = collision_layer
	bury()


## Bury it again (how it starts in a level).
func bury() -> void:
	state = State.BURIED
	collision_layer = 0
	velocity = Vector2.ZERO
	if _visual != null and _visual.has_method(&"show_buried"):
		_visual.call(&"show_buried", true)


func is_buried() -> bool:
	return state == State.BURIED or state == State.EMERGING


func _physics_process(delta: float) -> void:
	match state:
		State.BURIED:
			if _someone_near():
				_start_emerging()
		State.EMERGING:
			_left -= delta
			if _left <= 0.0:
				state = State.HUNTING
				collision_layer = _layer
		State.HUNTING:
			super(delta)
			var target := _spin_target()
			if target != null and is_on_floor():
				_start_spin()
		State.SPINNING:
			_spin(delta)
		State.RESTING:
			_left -= delta
			velocity.x = 0.0
			_apply_gravity(delta)
			move_and_slide()
			if _left <= 0.0:
				state = State.HUNTING


## The ultimate cannot reach it while buried (it is underground).
func hit_by_ultimate(from: Node = null) -> void:
	if is_buried():
		return
	super(from)


func _someone_near() -> bool:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) <= trigger_range and absf(offset.y) <= trigger_height:
			return true
	return false


func _start_emerging() -> void:
	state = State.EMERGING
	_left = emerge_time
	# When it emerges it faces the nearest player
	var players := players_by_distance()
	if not players.is_empty():
		facing = signi(players[0].global_position.x - global_position.x)
		if facing == 0:
			facing = 1
		_apply_facing()
	if _visual != null and _visual.has_method(&"emerge"):
		_visual.call(&"emerge")
	GameEvents.report(emerge_event, self)


func _spin_target() -> Player:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) <= spin_range and absf(offset.y) <= trigger_height:
			return player
	return null


func _start_spin() -> void:
	state = State.SPINNING
	_left = spin_time
	_flip_left = spin_flip
	_spun = false
	velocity.x = 0.0
	if _visual != null:
		_visual.fire()


func _spin(delta: float) -> void:
	_left -= delta
	_flip_left -= delta
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if _flip_left <= 0.0:
		_flip_left = spin_flip
		facing = -facing
		_apply_facing()
	if not _spun and spin_time - _left >= spin_hit_at:
		_spun = true
		_land_spin()
	if _left <= 0.0:
		state = State.RESTING
		_left = rest_time


## Halfway through the spin: anyone beside it (both sides count) takes a hit.
func _land_spin() -> void:
	for player in players_by_distance():
		if player.body_center().distance_to(body_center()) <= spin_radius:
			player.take_damage(roundi(spin_damage * Stage.damage_scale()), body_center(), self)


func is_spinning() -> bool:
	return state == State.SPINNING


func is_resting() -> bool:
	return state == State.RESTING
