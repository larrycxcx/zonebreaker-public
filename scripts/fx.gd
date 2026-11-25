class_name Fx
extends Node2D
## Effects layer: listens to `GameEvents` and spawns short-lived placeholder effects at the right spots.
##
## Gameplay code does not change by a line — it only reports "what happened" (a shot, a hit, a bullet hitting a wall),
## and this decides what to draw and where. The effect scenes are set by exported properties in the level; step 4 replaces the whole set with a skin pack.
## Effects are display-only Node2Ds without collision, hung under this node, so they disappear when the level unloads.

## These are the **default** effects: if the current skin pack has an effect with the same key it is used instead (see `SkinPack.EFFECT_KEYS`).
## A flash at the muzzle when firing.
@export var muzzle_flash_scene: PackedScene
## Sparks when a bullet hits a character (player or enemy).
@export var hit_spark_scene: PackedScene
## Sparks when a bullet hits something solid like a wall or the ground.
@export var impact_spark_scene: PackedScene
## Grenade explosion (scaled to the blast radius).
@export var explosion_scene: PackedScene

## Which events count as "a shot was fired". The event each character reports when firing is set in its scene (`Enemy.shoot_event`);
## add it here when adding a new enemy; `test_fx.gd` checks that every enemy's shoot_event in the level is in this list.
## Group of the effects layer. A fallen enemy needs somewhere to finish its death animation (its body is already deleted), so it hangs itself here.
const GROUP := &"fx"
const SHOOT_EVENTS: Array[StringName] = [&"player_shoot", &"enemy_shoot", &"turret_shoot", &"flyer_shoot"]
## These events mean "someone got hit"; sparks are drawn on whoever got hit.
const HIT_EVENTS: Array[StringName] = [&"enemy_hit", &"player_hurt"]


func _ready() -> void:
	add_to_group(GROUP)
	GameEvents.event_happened.connect(_on_event)


func _on_event(event: StringName, source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	if SHOOT_EVENTS.has(event):
		_flash_muzzle(source)
	elif HIT_EVENTS.has(event):
		_spawn(&"hit_spark", hit_spark_scene, _body_center(source))
	elif event == &"bullet_impact":
		# Reported when a bullet hits something solid; its own position is the impact point. The sparks splash back the way the bullet came.
		var spark := _spawn(&"impact_spark", impact_spark_scene, (source as Node2D).global_position)
		var flew: Variant = source.get(&"direction")
		if spark != null and spark.has_method(&"point") and flew is Vector2:
			spark.call(&"point", -(flew as Vector2))
	elif event == &"explosion":
		# Reported when a grenade explodes; sized by its blast radius.
		# Things with body_center (barrels: origin at the bottom) explode at the middle of their body; things like grenades whose origin is the centre stay as they are
		var blast := _spawn(&"explosion", explosion_scene, _body_center(source))
		if blast != null:
			blast.set(&"radius", source.get(&"blast_radius"))
	elif event == &"acid_splash":
		# An acid flask shattering (thrown by stage 5's scientists): the rules are the grenade's, the visual is a splash of acid instead;
		# if the pack has no such effect, fall back to the grenade explosion
		var splash := _spawn(&"acid_splash", explosion_scene, (source as Node2D).global_position)
		if splash != null:
			splash.set(&"radius", source.get(&"blast_radius"))
	elif event == &"ultimate_blast":
		# The ultimate's freeze has ended: an explosion on each enemy it hit (when this is reported the enemies are not destroyed yet, so their positions can be read).
		# Only the ultimate itself carries targets; when something else reports this event (e.g. while testing sounds) there is nothing to draw
		var targets: Variant = source.get(&"targets")
		if not targets is Array:
			return
		for target: Variant in targets:
			if not is_instance_valid(target):
				continue
			var at: Vector2 = target.body_center() if target.has_method(&"body_center") else target.global_position
			var blast := _spawn(&"explosion", explosion_scene, at)
			if blast != null:
				blast.set(&"radius", source.get(&"blast_radius"))


## Muzzle flash: the shooter remembers where this shot left the muzzle and which way it went (last_muzzle_position / last_shot_direction).
func _flash_muzzle(source: Node) -> void:
	var position_: Vector2 = source.get(&"last_muzzle_position")
	var direction: Vector2 = source.get(&"last_shot_direction")
	var flash := _spawn(&"muzzle_flash", muzzle_flash_scene, position_)
	if flash == null or direction == Vector2.ZERO:
		return
	# The pack's pixel art cannot be rotated 45°, so if it has point() let it pick the image drawn for that direction; the placeholder block still rotates as a whole
	if flash.has_method(&"point"):
		flash.call(&"point", direction)
	else:
		flash.rotation = direction.angle()


## Body centre: lower when the player is prone; use the method if it exists.
func _body_center(source: Node) -> Vector2:
	if source.has_method("body_center"):
		return source.call("body_center")
	return (source as Node2D).global_position


## Spawn an effect: use the current skin pack's if it has this key, otherwise the default scene set on the node.
func _spawn(key: StringName, fallback: PackedScene, position_: Vector2) -> Node2D:
	var scene := Skins.effect(key, fallback)
	if scene == null:
		return null
	var effect := scene.instantiate() as Node2D
	add_child(effect)
	effect.global_position = position_
	return effect
