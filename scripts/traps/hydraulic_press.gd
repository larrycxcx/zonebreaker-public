class_name HydraulicPress
extends Node2D
## Stage 2's trap, the "hydraulic press": a piston hanging from the ceiling that **slams all the way down to the floor**; touching it hurts.
##
## The node origin is the top-left corner of the frame (32×64), placed with the bottom edge on the floor.
## **Retracted, the bottom of the head is on row 31**, leaving exactly 32 pixels underneath — a standing player can walk through;
## slammed down the head reaches row 63, pressing all the way, and **lying prone does not save you**. The only way through: dash past when it pulls up.
## A row of presses is staggered (`phase`), so the gap opens one press after another.
##
## The hit check only looks at where the head and rod are in this frame (`HEAD`, measured from each frame of `Hammer.png`),
## independent of the look: the default skin draws blocks, the pack draws sprites, and the rules are the same. **No collision shape** — it blocks neither people nor bullets, it just must not be touched.
## Only hurts players (enemies walking past ignore it).

@export var skin_key := &"trap_press"
## Seconds of offset (presses in the same row get different values).
@export var phase := 0.0
@export var damage := 50
## Where the piston rod hangs from (world y): the bottom of the ceiling. The look extends the rod up to it; the rules do not use it.
@export var mount_y := 0.0
## How long each frame holds: rest retracted → slam down quickly → hold down a moment → pull back up slowly.
@export var durations: Array[float] = [1.2, 0.05, 0.05, 0.1, 0.12, 0.12, 0.12, 0.12]

const SIZE := Vector2(32, 64)
## Top and bottom of the head in each frame (row numbers within the frame). Measured from `Hammer.png`.
const HEAD := [Vector2i(10, 31), Vector2i(27, 53), Vector2i(44, 63), Vector2i(40, 62),
	Vector2i(42, 63), Vector2i(32, 53), Vector2i(22, 43), Vector2i(12, 33)]
## Left and right of the rod (columns within the frame). The head is the full 32 wide.
const ROD := Vector2i(7, 24)
## The hit check gives 2 pixels compared with the picture: in the last frame of pulling back the bottom of the head is on row 33, just grazing a standing player's head —
## on screen it looks "already retracted", and getting hit then would feel unfair.
const GRACE := 2

var frame := 0
var _time := 0.0
var _visual: Node


func _ready() -> void:
	_visual = Skins.build_appearance(self, skin_key)
	if _visual != null and _visual.has_method(&"set_mount"):
		_visual.call(&"set_mount", mount_y - global_position.y)
	_show()


func _physics_process(delta: float) -> void:
	_time += delta
	var now := TrapTimeline.frame_at(_time, durations, phase)
	if now != frame:
		frame = now
		_show()
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		if hits(player.hit_box()):
			player.take_damage(roundi(damage * Stage.damage_scale()), head_center(), self)


## Where the head and rod are in this frame (world coordinates).
func danger_rects() -> Array[Rect2]:
	var head: Vector2i = HEAD[frame]
	var bottom := float(head.y + 1 - GRACE)
	var out: Array[Rect2] = []
	out.append(Rect2(global_position + Vector2(ROD.x, 0.0), Vector2(ROD.y - ROD.x + 1, head.x)))
	out.append(Rect2(global_position + Vector2(0.0, head.x), Vector2(SIZE.x, bottom - head.x)))
	return out


func hits(box: Rect2) -> bool:
	for rect in danger_rects():
		if rect.intersects(box):
			return true
	return false


func head_center() -> Vector2:
	var head: Vector2i = HEAD[frame]
	return global_position + Vector2(SIZE.x / 2.0, (head.x + head.y) / 2.0)


## How high the bottom of the head is above the floor (for tests: retracted, a standing player gets through).
func clearance() -> float:
	return SIZE.y - float(HEAD[frame].y + 1 - GRACE)


## What the placeholder colour blocks draw (world coordinates converted to local).
func art_rects(at_frame: int) -> Array[Rect2]:
	var keep := frame
	frame = at_frame
	var out: Array[Rect2] = []
	for rect in danger_rects():
		out.append(Rect2(rect.position - global_position, rect.size))
	frame = keep
	return out


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_frame"):
		_visual.call(&"show_frame", frame)
