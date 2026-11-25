class_name PoisonCloud
extends Node2D
## A poison cloud (2026-11, stage 5): it hangs where it is for a while and **players standing inside get poisoned** (`status/poison.tres`);
## after leaving, the poison lasts a little longer (the status's own duration). Staying inside keeps refreshing it; damage does not stack.
## The drops dripped by 5_f (the ceiling emitter) burst into one of these on landing; other things could release them later.
##
## The node origin is the centre of the cloud. The hit check is a circle (`radius`); touching the player's hitbox counts as inside.
## The look only draws (the pack draws `Acid2`, a cloud slowly spreading out; the placeholder a translucent green circle); gameplay does not depend on it.
## Only hurts players; blocks neither people nor bullets (no collision shape).

const GROUP := &"poison_clouds"

@export var skin_key := &"poison_cloud"
@export var status: StatusEffect = preload("res://status/poison.tres")
## Radius of the hit circle: fully spread, the cloud in the art is about 48 across.
@export var radius := 24.0
## How long it lasts (seconds).
@export var lifetime := 1.8

var age := 0.0
var _visual: Node


func _ready() -> void:
	add_to_group(GROUP)
	_visual = Skins.build_appearance(self, skin_key)
	_show()


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.is_alive() and touches(player.hit_box()):
			player.apply_status(status)
	_show()


## Does this box touch the cloud's circle (world coordinates)?
func touches(box: Rect2) -> bool:
	var nearest := Vector2(clampf(global_position.x, box.position.x, box.end.x),
		clampf(global_position.y, box.position.y, box.end.y))
	return nearest.distance_to(global_position) <= radius


## How far it has spread (0 just burst → 1 fully gone).
func progress() -> float:
	return clampf(age / lifetime, 0.0, 1.0)


## The placeholder blocks (`TrapBlocks`) do not draw circles, so give them a square here; a look with `show_progress` takes that route instead.
func art_rects(_frame: int) -> Array[Rect2]:
	return [Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0)]


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_progress"):
		_visual.call(&"show_progress", progress())
