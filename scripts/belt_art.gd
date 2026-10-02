class_name BeltArt
extends Node2D
## 传送带的画面（2026-10）：在砖那一层上面，把每条传送带中间那一截的齿**朝它带的方向滚动**。
## 砖（`TileArt`）画的是静止的传送带（两头的收边 + 中间的齿），这里只把中间那段换成会动的——
## 玩家一眼看得出这条带往哪边走。纯显示，规则全在平台的 `conveyor` 上。

@export var atlas: Texture2D
@export var columns := 9
@export var tile_size := 32
## 中间那块传送带砖的编号（素材 `IndustrialTile_75`，齿每 4 像素一个）
@export var tile := 75
## 每条带：x, y, 宽, 速度（px/s，正数往右），四个一组
@export var belts: PackedFloat32Array = PackedFloat32Array()

const PITCH := 4
## 两头留给收边砖的宽度、每次从砖里取的那一截（取在砖中间，挪 0~3 像素也不会取到砖外面）
const CAP := 8
const CHUNK := 16
const CELL_H := 16

var _time := 0.0


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
		# 齿往右走 = 取图的位置往左挪
		var shift := posmod(-int(floor(_time * speed)), PITCH)
		var at := x + CAP
		var end := x + width - CAP
		while at < end:
			var w := minf(CHUNK, end - at)
			draw_texture_rect_region(atlas, Rect2(at, y, w, CELL_H),
				Rect2(src.x + CAP + shift, src.y, w, CELL_H))
			at += w

