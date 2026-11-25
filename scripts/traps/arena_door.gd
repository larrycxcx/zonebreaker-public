class_name ArenaDoor
extends StaticBody2D
## Stage 5's **mid-level boss room door** (agreed with the user in 2026-11: the mutant gunner waits in a sealed room, and the door ahead only opens once it is dead).
## The node origin is the door's top-left corner, 32×64 (2×4 cells in the map, `[` entry, `]` exit), with its bottom edge on the floor;
## above the door it has to be solid all the way up to the ceiling (like the blast gate; the grid map self-check checks this), or you could jump over it.
##
## - **Entry door** (`exit_door` off): starts open. Once the room's mid-level boss has appeared and **every living player is through the door**
## (to its right) it shuts — it only closes once everyone is in, never trapping anyone in the doorway or locking them out.
## - **Exit door** (`exit_door` on): starts shut, **opens only when the mid-level boss dies**. The entry door opens at the same time.
## Shut it is a wall (world layer: blocks players, enemies and bullets); open its collision shape is turned off. Opening / closing it retracts into / drops from the ceiling over `move_time` seconds,
## but the rule only looks at "open or not": the moment it drops it is a wall (anyone standing under it is first pushed to the room's side).
## "Which boss belongs to this room": a boss with `ends_level` off, which reports `GameEvents.boss_appeared` when it appears.

@export var skin_key := &"arena_door"
@export var exit_door := false
@export var move_time := 0.4

const SIZE := Vector2(32, 64)

var is_open := true
var _ratio := 1.0
var _boss: Boss
var _visual: Node

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Skins.build_appearance(self, skin_key)
	is_open = not exit_door
	_ratio = 1.0 if is_open else 0.0
	# One that starts shut (the exit door) pushes nobody: the player nodes are not ready yet at this point, and nobody stands under it anyway
	_apply(false)
	GameEvents.boss_appeared.connect(_on_boss_appeared)


func _on_boss_appeared(boss: Node) -> void:
	var it := boss as Boss
	if it == null or it.ends_level or _boss != null:
		return
	_boss = it
	it.died.connect(_on_boss_died)


func _on_boss_died() -> void:
	set_open(true)


func _physics_process(delta: float) -> void:
	if not exit_door and is_open and _boss != null and is_instance_valid(_boss) and _boss.health > 0 \
			and _everyone_inside():
		set_open(false)
	var want := 1.0 if is_open else 0.0
	if not is_equal_approx(_ratio, want):
		_ratio = move_toward(_ratio, want, delta / move_time)
		_show()


## Every living player is to the right of the door (all the way through it).
func _everyone_inside() -> bool:
	var any := false
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		any = true
		if player.hit_box().position.x < global_position.x + SIZE.x:
			return false
	return any


func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	_apply(true)


func box() -> Rect2:
	return Rect2(global_position, SIZE)


func _apply(push: bool) -> void:
	_shape.set_deferred(&"disabled", is_open)
	if not is_open and push:
		# Anyone still standing under the door the moment it drops: push them to the room's side (right of the entry door, left of the exit door)
		for node in get_tree().get_nodes_in_group(&"player"):
			var player := node as Player
			if player != null and player.hit_box().intersects(box()):
				var half := player.hit_box().size.x / 2.0
				player.global_position.x = global_position.x + SIZE.x + half + 1.0 if not exit_door \
					else global_position.x - half - 1.0
	_show()


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_open"):
		_visual.call(&"show_open", _ratio)


func open_ratio() -> float:
	return _ratio
