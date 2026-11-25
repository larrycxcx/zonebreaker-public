class_name TileArt
extends Node2D
## The "tiles" of layered stages (2026-10): draws the skin pack's tiles cell by cell from the grid map, **display only** —
## collision is handled by the platform nodes in the level (hidden and not drawn in stages built from grid maps); this only makes it look good.
##
## Like scenery (`Prop`) it references its texture by path: which tile each cell uses is worked out by the build script (`map_build.py`)
## from the shape of that solid area (top edges, sides, corners and insides each get their own tile) and stored in `cells`.
##
## The art's tiles are 32×32 and the cells 16×16, so **each cell draws a quarter of a tile**: `cells` holds groups of four numbers —
## the cell's column, row, the tile number (which tile of the atlas, counting from 1) and which corner to take (0 top-left / 1 top-right / 2 bottom-left / 3 bottom-right).
## A top-edge cell takes the top half, a left-edge cell the left half... so even a 16-thick floor gets the full highlight edge.

## One atlas with every tile: `columns` tiles per row, tile n in column (n-1) % columns and row (n-1) / columns.
@export var atlas: Texture2D
## Path of the atlas. The level scene stores this (not a direct reference to the texture): the tiles are third-party art missing from the public build,
## and a direct reference would stop the whole level scene from loading. `_ready` only loads it if the file is there; otherwise nothing is drawn
## and the level (`main.gd._show_bare_terrain()`) shows the hidden collision platforms as terrain instead.
@export_file("*.png") var atlas_path := ""
@export var columns := 9
@export var tile_size := 32
@export var cells: PackedInt32Array = PackedInt32Array()
## Tint for the whole layer (the back wall is darkened a little so the things in front stand out).
@export var tint := Color.WHITE

const CELL := 16


func _ready() -> void:
	if atlas == null and not atlas_path.is_empty() and ResourceLoader.exists(atlas_path):
		atlas = load(atlas_path) as Texture2D
	queue_redraw()


func _draw() -> void:
	if atlas == null:
		return
	var half := tile_size / 2
	for i in range(0, cells.size(), 4):
		var tile := cells[i + 2] - 1
		var quarter := cells[i + 3]
		var src := Vector2((tile % columns) * tile_size + (quarter % 2) * half,
			(tile / columns) * tile_size + (quarter / 2) * half)
		draw_texture_rect_region(atlas, Rect2(cells[i] * CELL, cells[i + 1] * CELL, CELL, CELL),
			Rect2(src, Vector2(half, half)), tint)
