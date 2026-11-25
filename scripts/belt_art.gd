class_name BeltArt
extends Node2D
## Conveyor art (2026-10): above the tile layer, the teeth in the middle stretch of each belt **scroll in the direction it carries**.
## The tiles (`TileArt`) draw a still belt (end caps + teeth in the middle); this only replaces the middle with a moving one —
## so the player can tell at a glance which way the belt goes. Pure presentation; the rule lives in the platform's `conveyor`.

@export var atlas: Texture2D
## Path of the tile atlas. The level scene stores this (not a direct reference to the texture): the tiles are third-party art missing from the public build,
## and a direct reference would stop the whole level scene from loading. `_ready` only loads it if the file is there; otherwise nothing is drawn
## and the level (`main.gd._show_bare_terrain()`) shows the hidden collision platforms as terrain instead.
@export_file("*.png") var atlas_path := ""
@export var columns := 9
@export var tile_size := 32
## Number of the middle conveyor tile (art `IndustrialTile_75`, one tooth every 4 pixels)
@export var tile := 75
## Each belt: x, y, width, speed (px/s, positive = right), four values per belt
@export var belts: PackedFloat32Array = PackedFloat32Array()

const PITCH := 4
## Width left for the end-cap tiles at both ends, and the slice taken from the tile each time (taken from the middle, so shifting it 0~3 pixels never reads outside the tile)
const CAP := 8
const CHUNK := 16
const CELL_H := 16

var _time := 0.0


func _ready() -> void:
	if atlas == null and not atlas_path.is_empty() and ResourceLoader.exists(atlas_path):
		atlas = load(atlas_path) as Texture2D
	if atlas == null:
		set_process(false)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if atlas == null:
		return
	var index := tile - 1
	var src := Vector2((index % columns) * tile_size, (index / columns) * tile_size)
	for i in range(0, belts.size() - 3, 4):
		var x := belts[i]
		var y := belts[i + 1]
		var width := belts[i + 2]
		var speed := belts[i + 3]
		# Teeth moving right = the source rect moves left
		var shift := posmod(-int(floor(_time * speed)), PITCH)
		var at := x + CAP
		var end := x + width - CAP
		while at < end:
			var w := minf(CHUNK, end - at)
			draw_texture_rect_region(atlas, Rect2(at, y, w, CELL_H),
				Rect2(src.x + CAP + shift, src.y, w, CELL_H))
			at += w

