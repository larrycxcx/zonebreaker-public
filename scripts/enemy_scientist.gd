class_name EnemyScientist
extends EnemyGrenadier
## Stage 5's scientists (5-A / 5-B): patrol, throw **acid flasks** forward (a kind of enemy grenade, `acid_flask.tscn`:
## it shatters on whatever it touches and splashes a small area, same rules as a grenade), and can **turn into a mutant** (5-C).
##
## Transforming: stands still and plays the `transform` frames (the last frame already looks like the mutant and holds there),
## and after `transform_time` seconds it is replaced on the spot by a mutant (`mutant_scene`) and quietly disappears — **no reward**;
## the reward comes from killing the mutant. While transforming it can still be hit, and killing it then is an ordinary death (with reward), so that moment is an opening.
## - 5-A (`transform_on_sight` off): it only transforms **when hit without dying, or when the player gets within `transform_range`**.
## To save yourself trouble, kill it in one go before it changes.
## - 5-B (`transform_on_sight` on): **transforms as soon as it sees the player**, never throws a flask.

@export_group("Transform")
## What it turns into. Leave empty to never transform (a scientist that only throws flasks).
@export var mutant_scene: PackedScene
## Transform as soon as it sees the player (5-B); off means it transforms when hit / approached (5-A).
@export var transform_on_sight := false
## How close the player has to get to trigger the transformation (5-A).
@export var transform_range := 56.0
## How long the transformation takes (the stretch where it stands still and can be hit).
@export var transform_time := 0.9
@export var transform_event := &"chaser_alert"

var _transforming := false
var _transform_left := 0.0


func is_transforming() -> bool:
	return _transforming


func _physics_process(delta: float) -> void:
	if _transforming:
		_transform_left -= delta
		velocity.x = 0.0
		_apply_gravity_only(delta)
		if _transform_left <= 0.0:
			_become_mutant()
		return
	super(delta)
	if mutant_scene == null or health <= 0:
		return
	if transform_on_sight:
		if _sees_a_player():
			start_transform()
	elif _player_within(transform_range):
		start_transform()


## 5-B transforms on sight, so it never throws: "engaged" = it has seen you, and once it has, it stands still and transforms.
func throw_target() -> Node2D:
	if transform_on_sight and mutant_scene != null:
		return null
	return super()


func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if health > 0 and not _transforming and mutant_scene != null and not is_queued_for_deletion():
		start_transform()
	elif _transforming and health > 0 and _visual != null and _visual.has_method(&"play_once"):
		# The hurt frames of a hit interrupted the transform clip; put the transform pose back
		_visual.call(&"play_once", &"transform", true)


func start_transform() -> void:
	if _transforming or mutant_scene == null:
		return
	_transforming = true
	_transform_left = transform_time
	velocity.x = 0.0
	if _visual != null and _visual.has_method(&"play_once"):
		_visual.call(&"play_once", &"transform", true)
	GameEvents.report(transform_event, self)


func _become_mutant() -> void:
	var mutant := mutant_scene.instantiate() as Node2D
	get_parent().add_child(mutant)
	mutant.global_position = global_position
	mutant.set(&"facing", facing)
	if mutant.has_method(&"face"):
		mutant.call(&"face", facing)
	# Quietly disappear: no die(), no death report, no reward (the reward is on the mutant)
	queue_free()


func _sees_a_player() -> bool:
	for player in players_by_distance():
		if within_reach(global_position.distance_to(player.global_position)) \
				and has_line_of_sight(player.body_center()):
			return true
	return false


func _player_within(distance: float) -> bool:
	for player in players_by_distance():
		if player.global_position.distance_to(global_position) <= distance:
			return true
	return false


func _apply_gravity_only(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	move_and_slide()
