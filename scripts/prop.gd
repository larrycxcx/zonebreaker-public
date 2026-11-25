class_name Prop
extends Sprite2D
## Scenery in a stage: benches, trees, rocks, bushes, fountains and so on.
##
## **Display only**: no colliders anywhere in the tree, and it takes part in no checks — the same rule as effects.
## In a stage they hang under the `Props` node, **drawn behind everything** (after the backdrop, before the terrain),
## so however dense they are they never hide enemies, bullets or terrain; delete `Props` entirely and the game still runs.
##
## The texture's **bottom-left corner sits on the node's position** (`centered = false`, then moved up by its height),
## so placing it is just a matter of saying "which surface it stands on".
##
## Animated ones are a horizontal strip of frames (fountain 288×72 = 4 frames × 72), played frame by frame through `region_rect`.

## Path of the texture. **The level scene stores a path, not a direct reference**: scenery is third-party art, missing from the public build,
## and a direct reference would stop the whole level scene from loading; with a path a missing one is simply not drawn (loaded in `_ready`, left empty if absent).
@export_file("*.png") var texture_path := ""
## Bottom-left corner of the texture on the node's position (how scenery is placed). false = centred (how decals are placed: the digit on a sign sits in the middle of the disc).
@export var bottom_left := true
## How many frames are laid out side by side in the texture. 1 = static, no `_process`.
@export var frames := 1
## Frames per second for animated ones.
@export var fps := 8.0

var _time := 0.0


func _ready() -> void:
	if texture == null and not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	if not bottom_left:
		set_process(false)
		return
	centered = false
	if texture == null:
		set_process(false)
		return
	# The position says "where the bottom edge of the texture lands", so move the whole thing up by its height
	offset.y = -texture.get_height()
	if frames <= 1:
		set_process(false)
		return
	region_enabled = true
	_show_frame(0)


func _process(delta: float) -> void:
	_time += delta
	_show_frame(int(_time * fps) % frames)


func _show_frame(frame: int) -> void:
	var wide := texture.get_width() / float(frames)
	region_rect = Rect2(frame * wide, 0.0, wide, texture.get_height())
	offset.x = 0.0
