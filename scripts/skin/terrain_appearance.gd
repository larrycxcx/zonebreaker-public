class_name TerrainAppearance
extends Appearance
## 精灵图版的地形外观：按平台大小用「九宫格」画一张源图——四个角原样，四条边和中间**平铺**（不拉伸，像素不会糊）。
##
## 源图由 `tools/terrain_build.py` 从地砖拼出来；怎么切（四条边各多宽）写在外观场景里。
## 平台的碰撞体、单向与否全都不动，这里只管画：平台在 `_ready` 里装上外观后调 `fit(大小)`。
## `hang` 是画面挂在判定框下面的像素数（浮空平台底下那一排下垂的碎块），只往下挂、不往上长，
## 所以站立面永远就是判定框的顶边。

## 源图。
@export var texture: Texture2D
## 源图四条边的宽度：这几圈原样画，中间那块平铺。
@export var left := 0
@export var right := 0
@export var top := 0
@export var bottom := 0
## 画面比判定框多往下挂几像素。
@export var hang := 0

var _size := Vector2.ZERO


func _ready() -> void:
	# 不调 super()：基类那套按位置镜像子节点的翻转法是给角色的占位方块用的，地形不翻转。
	queue_redraw()


## 平台多大（= 碰撞体的大小，原点在左上角）。
func fit(size: Vector2) -> void:
	_size = size
	queue_redraw()


## 画出来占多大（测试用）：宽和平台一样，高多出 hang。
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


## 一个方向上怎么铺：把目标长度 `length` 切成若干段，每段是 [目标起点, 长度, 源图起点]，
## 源图对应那段和目标一样长（只裁不缩）。头 `start` 和尾 `end` 各一段原样画，中间用源图中间那截循环铺满；
## 目标比两头加起来还短时，两头按比例各让一点，保证头尾的描边都还在。
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
