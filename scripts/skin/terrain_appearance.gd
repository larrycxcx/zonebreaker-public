class_name TerrainAppearance
extends Appearance
## Sprite version of the terrain look: draws one source image as a "nine-slice" to the platform's size — the four corners as they are, the four edges and the middle **tiled** (never stretched, so the pixels stay sharp).
##
## The source images are assembled from tiles by `tools/terrain_build.py`; how they are sliced (how wide each edge is) is written in the appearance scene.
## The platform's collision shape and one-way setting are never touched, this only draws: the platform calls `fit(size)` after installing the look in `_ready`.
## `hang` is how many pixels the picture hangs below the hitbox (the row of dangling bits under a floating platform); it only hangs down, never grows up,
## so the standing surface is always the top of the hitbox.

## Source image.
@export var texture: Texture2D
## Widths of the four edges of the source image: these bands are drawn as they are, the middle is tiled.
@export var left := 0
@export var right := 0
@export var top := 0
@export var bottom := 0
## How many pixels further down the picture hangs than the hitbox.
@export var hang := 0

var _size := Vector2.ZERO


func _ready() -> void:
	# No super(): the base class flips by mirroring child positions, which is for the characters' placeholder blocks; terrain never flips.
	queue_redraw()


## Size of the platform (= the collision shape's size, origin at the top-left corner).
func fit(size: Vector2) -> void:
	_size = size
	queue_redraw()


## How big the drawing is (for tests): as wide as the platform, hang taller.
func drawn_size() -> Vector2i:
	return Vector2i(roundi(_size.x), roundi(_size.y) + hang)


func _draw() -> void:
	if texture == null or _size == Vector2.ZERO:
		return
	var drawn := drawn_size()
	var source := Vector2i(texture.get_width(), texture.get_height())
	for column in pieces(drawn.x, source.x, left, right):
		for row in pieces(drawn.y, source.y, top, bottom):
			draw_texture_rect_region(texture,
				Rect2(column[0], row[0], column[1], row[1]),
				Rect2(column[2], row[2], column[1], row[1]))


## How to lay out one direction: cut the target length `length` into segments, each [target start, length, source start],
## with the matching source segment as long as the target (cropped, never scaled). The head `start` and tail `end` are drawn once as they are, the middle of the source repeats to fill the rest;
## when the target is shorter than head and tail together, both give up a share proportionally so the outlines at both ends are still there.
static func pieces(length: int, source: int, start: int, end: int) -> Array:
	var out := []
	var tail := mini(end, length / 2)
	var head := mini(start, length - tail)
	if head > 0:
		out.append([0, head, 0])
	var period := source - start - end
	var at := head
	while period > 0 and at < length - tail:
		var step := mini(period, length - tail - at)
		out.append([at, step, start])
		at += step
	if tail > 0:
		out.append([length - tail, tail, source - tail])
	return out
