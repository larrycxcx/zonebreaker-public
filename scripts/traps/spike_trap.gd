class_name SpikeTrap
extends Node2D
## Stage 5's (lab) trap, "spikes": a thin base in the floor that **thrusts out three spikes in rhythm**; touching them while out hurts.
##
## The node origin is the top-left corner of the frame (32×32). The base (rows 28~31 of the frame) **sinks into the top 4 rows of the floor**,
## so it is placed with the bottom of the frame at "floor surface + 4": the spikes grow out of the floor surface and players stand on the floor as usual.
## The art `Spikes.png` has 6 frames: 0 tips just showing, 1 fully retracted, 2 springing out, 3 fully out, 4 pulling back, 5 a little stub showing.
## **At rest it holds frame 5 (a little stub showing)**: you can see from afar that there are spikes here (the user, 2026-11: "by default you should see the part sticking out of the floor"),
## and that stub is below the harmful height, so standing on it does no damage. **The warning is "pulling in first"**: before it stabs, the spikes retract into the floor (0 → 1),
## then spring out (2), hold fully out (3), pull back (4) and show their stubs again (5). "The spikes suddenly vanished" is the signal, like a wind-up.
## Several side by side are staggered (`phase`), so the gaps open one after another — the same idea as the hydraulic presses.
##
## The hit check only looks at how far the spikes reach in this frame (`TIPS`, measured per frame from the art), independent of the look. **No collision shape**:
## the base is too thin, players stand on the floor under it as usual; the spikes block neither people nor bullets, they just must not be touched. Only hurts players.

@export var skin_key := &"trap_spikes"
@export var phase := 0.0
@export var damage := 40
## Timeline: how long each step holds, matching the frames in `ORDER`. Resting with the stub out lasts long, pulling in (the warning) leaves enough time to react, fully out holds a moment.
@export var durations: Array[float] = [1.4, 0.08, 0.35, 0.06, 0.5, 0.08]

const SIZE := Vector2(32, 32)
## Which art frame each step of the timeline draws: resting with the stub out → pulling down → fully in (the warning) → springing out → fully out → pulling back.
const ORDER := [5, 0, 1, 2, 3, 4]
## The resting frame (a little stub out) and the warning frame (fully in).
const REST := 5
const WARN := 1
## Row of the spike tips in each frame (within the frame). Tips just showing (0), fully in (1) and the stub (5) are all below the harmful height.
const TIPS := [27, 28, 13, 12, 17, 22]
## Row of the floor surface in the frame (where the spikes grow from).
const SURFACE := 28
## Only harmful when sticking out more than this: the stub showing at rest (frame 5, 6 pixels) only tells you there are spikes; stepping on it should not cost health.
const HARMFUL := 8
## Horizontal extent of the spikes (columns within the frame): three spikes at x 4..27.
const SPAN := Vector2i(4, 27)

var frame := REST
var _time := 0.0
var _visual: Node


func _ready() -> void:
	_visual = Skins.build_appearance(self, skin_key)
	_show()


func _physics_process(delta: float) -> void:
	_time += delta
	var now: int = ORDER[TrapTimeline.frame_at(_time, durations, phase)]
	if now != frame:
		frame = now
		_show()
	if not is_armed():
		return
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		if danger_rect().intersects(player.hit_box()):
			player.take_damage(roundi(damage * Stage.damage_scale()), danger_rect().get_center(), self)


## How far the spikes stick out of the floor (pixels).
func height() -> float:
	return float(SURFACE - TIPS[frame])


## Is this frame harmful?
func is_armed() -> bool:
	return height() >= HARMFUL


## Where the spikes are (world coordinates). A zero-height line when they are not out.
func danger_rect() -> Rect2:
	var top := float(TIPS[frame])
	return Rect2(global_position + Vector2(SPAN.x, top), Vector2(SPAN.y - SPAN.x + 1, SURFACE - top))


## What the placeholder colour blocks draw: a strip for the base + the spikes that are out.
func art_rects(at_frame: int) -> Array[Rect2]:
	var top := float(TIPS[at_frame])
	return [Rect2(0.0, SURFACE, SIZE.x, SIZE.y - SURFACE),
		Rect2(SPAN.x, top, SPAN.y - SPAN.x + 1, SURFACE - top)]


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_frame"):
		_visual.call(&"show_frame", frame)
