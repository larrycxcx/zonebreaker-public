class_name BlastGate
extends StaticBody2D
## Stage 2's trap, the "blast gate": a 64-tall door that **is a wall when shut, passable when open, and hurts anyone caught as it closes**.
##
## The node origin is the top-left corner of the frame (32×64), with the bottom edge on the ground; the level puts a stretch of solid wall above the door up to the top of the view
## (`gates` in `level_build.py`) — the door is only 64 tall and a jump reaches 87, so without sealing it above you would just jump over and the door would be pointless.
##
## - **Shut** (frames 0, 1, 7): the collision shape is on and blocks players, enemies and bullets (world layer, like a wall).
## - **Open** (frames 2~6): the collision shape is off. Fully open only a few pixels of edge remain at the top and bottom; that is picture, it touches nobody.
## - **Closing** (frames 6, 7): anyone still in the doorway takes a hit and is pushed out —
## anyone still inside the moment it shuts is moved straight to the nearest side and **never stuck inside the wall**.
## Only hurts players. Use `phase` to stagger the rhythm.

@export var skin_key := &"trap_gate"
@export var phase := 0.0
@export var damage := 50
## Rest shut → open → stay open → close.
@export var durations: Array[float] = [1.6, 0.08, 0.08, 0.08, 1.4, 0.08, 0.08, 0.08]
## How hard it pushes out anyone caught.
@export var push := Vector2(220, -160)

const SIZE := Vector2(32, 64)
## Which frames are shut (solid) and which are closing (catching people).
const SHUT := [0, 1, 7]
const CLOSING := [6, 7]
## Which stretches of rows the door panel covers in each frame, measured from `Entry.png`: when opening, the top and bottom halves retract toward the ends.
const PANELS := [[Vector2i(0, 63)], [Vector2i(0, 63)], [Vector2i(0, 25), Vector2i(37, 63)],
	[Vector2i(0, 6), Vector2i(57, 63)], [Vector2i(0, 3), Vector2i(60, 63)],
	[Vector2i(0, 6), Vector2i(57, 63)], [Vector2i(0, 25), Vector2i(37, 63)], [Vector2i(0, 63)]]

var frame := 0
var _time := 0.0
var _visual: Node

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Skins.build_appearance(self, skin_key)
	frame = TrapTimeline.frame_at(0.0, durations, phase)
	_apply()


func _physics_process(delta: float) -> void:
	_time += delta
	var now := TrapTimeline.frame_at(_time, durations, phase)
	if now == frame:
		return
	frame = now
	_apply()
	if frame in CLOSING:
		_squeeze()


func is_shut() -> bool:
	return frame in SHUT


## The strip the door occupies (world coordinates).
func column() -> Rect2:
	return Rect2(global_position, SIZE)


func _apply() -> void:
	# Changing the collision shape has to wait until the physics step is done (changing it inside a physics callback is an error)
	_shape.set_deferred(&"disabled", not is_shut())
	if _visual != null and _visual.has_method(&"show_frame"):
		_visual.call(&"show_frame", frame)


## The door is closing: anyone still in the doorway takes a hit and is pushed out. Anyone still inside the moment it shuts is moved straight to the nearest side.
func _squeeze() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not (player.is_alive() or player.is_downed()):
			continue
		var box := player.hit_box()
		if not column().intersects(box):
			continue
		var middle := global_position.x + SIZE.x / 2.0
		var side := 1.0 if player.global_position.x >= middle else -1.0
		if player.is_alive():
			player.take_damage(roundi(damage * Stage.damage_scale()), Vector2(middle, box.get_center().y), self)
			player.shove(Vector2(push.x * side, push.y))
		if is_shut():
			var half := box.size.x / 2.0 + 1.0
			player.global_position.x = global_position.x - half if side < 0.0 else global_position.x + SIZE.x + half


## What the placeholder colour blocks draw (local coordinates).
func art_rects(at_frame: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for span: Vector2i in PANELS[at_frame]:
		out.append(Rect2(0.0, span.x, SIZE.x, span.y - span.x + 1))
	return out
