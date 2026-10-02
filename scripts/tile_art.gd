class_name TileArt
extends Node2D
## 分层关卡的「砖」（2026-10）：按格子地图一格一格地画素材包的砖，**纯显示**——
## 碰撞是关卡里那些平台节点管的（它们在格子地图生成的关卡里藏起来、不画），这里只管好看。
##
## 和装饰（`Prop`）一样是按贴图路径直接引用的：哪一格用哪块砖是生成脚本（`map_build.py`）按
## 这块实心区域的形状算好的（顶边、侧边、拐角、内部各用各的砖），存在 `cells` 里。
##
## 素材的砖是 32×32，格子是 16×16，所以**一格画一块砖的四分之一**：`cells` 里每四个数一组——
## 格子的列、行、砖的编号（总图里第几块，从 1 数）、取哪个角（0 左上 / 1 右上 / 2 左下 / 3 右下）。
## 顶边那一格取上半、左边那一格取左半……这样 16 厚的楼板也带着完整的高光边。

## 所有砖排成的一张总图：一行 `columns` 块，编号 n 在第 (n-1) % columns 列、第 (n-1) / columns 行。
@export var atlas: Texture2D
@export var columns := 9
@export var tile_size := 32
@export var cells: PackedInt32Array = PackedInt32Array()
## 整层的染色（背景墙压暗一点，好让前面的东西跳出来）。
@export var tint := Color.WHITE

const CELL := 16


func _ready() -> void:
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
