@tool
class_name Ladder
extends Node2D
## Ladder (added 2026-10): connects two layers. **The node's origin is the top centre of the ladder** — the surface of the floor above;
## the ladder extends `height` down from there, its foot resting on the floor of the layer below.
##
## - The player grabs it by pressing "up" in front of it (or "down" standing on top of it) and climbs up and down, with no gravity and **no shooting**;
## at the top they step off onto the floor, at the bottom they let go on landing; jump drops off (with a direction it jumps off that way). See `Player._climb()`.
## - **The top of the ladder has its own small one-way platform** (`cap`): the floor above has a hole where the ladder is,
## and without a cover you would fall in walking past; with a one-way cover you only go down the ladder by pressing "down" on it.
## It is invisible — on screen it is just the top of the ladder; the cover is only a rule.
## - Enemies do not climb ladders (to their patrol the ladder is not a wall; they just walk past).
## - The rules live on the body (`grab_rect()`, `top_y()`, `bottom_y()`); the look is up to `Visual` (`LadderAppearance`).

const GROUP := &"ladders"
## Width of the cover (the hole left in the floor above): a little wider than a person (24), so you can pass through it along the ladder.
const CAP_WIDTH := 32.0
const CAP_THICK := 16.0

@export var height := 96.0:
	set(value):
		height = value
		_apply()
## Ladder width (hit check): you can only grab it with your body centre this close to the ladder's centre line.
@export var width := 24.0
@export var skin_key := &"ladder"
## Whether the top needs a cover (not when the ladder top sticks out of the ground and there is no floor above it).
@export var cap := true

var _visual: Node
var _cap: Platform


func _ready() -> void:
	add_to_group(GROUP)
	if not Engine.is_editor_hint():
		_visual = Skins.build_appearance(self, skin_key)
		if cap:
			_cap = (load("res://scenes/platform.tscn") as PackedScene).instantiate() as Platform
			_cap.name = "Cap"
			_cap.one_way = true
			_cap.size = Vector2(CAP_WIDTH, CAP_THICK)
			_cap.position = Vector2(-CAP_WIDTH / 2.0, 0.0)
			_cap.visible = false
			add_child(_cap)
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	var visual := _visual if _visual != null else get_node_or_null("Visual")
	if visual != null and visual.has_method(&"fit"):
		visual.call(&"fit", Vector2(width, height))


## The cover on top (collision with it is ignored temporarily while climbing through it).
func cap_body() -> Platform:
	return _cap


func top_y() -> float:
	return global_position.y


func bottom_y() -> float:
	return global_position.y + height


## The area where it can be grabbed (world coordinates): half the width either side of the centre line, from top to bottom.
func grab_rect() -> Rect2:
	return Rect2(global_position.x - width / 2.0, top_y(), width, height)
