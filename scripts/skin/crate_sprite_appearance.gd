class_name CrateSpriteAppearance
extends Appearance
## 机关的一条贴图（油桶 1 帧、箱子 8 帧）。箱子：`Chest.png` 前三帧一模一样（完好），
## 所以「越打越破」靠**挨一下抖一下、越打越暗**；打烂了把后几帧（3~7，掀开散架）播一遍。
## 玩法只调 `show_damage(打到几成, 打烂了没有)`，和别的机关一样不碰贴图。油桶连这个都不调，一直是第 0 帧。

@export var strip: Texture2D
@export var frames := 8
@export var break_fps := 12.0
## 贴图左上角相对节点原点画在哪（箱子原点在左上角、油桶在桶底正中）
@export var at := Vector2.ZERO
## 挨打时横着抖几像素
const SHAKE := 1.0

var _stage := 0.0
var _broken := false
var _broken_for := 0.0


func _ready() -> void:
	pass


var _shake := 0.0


func show_damage(stage: float, broken: bool) -> void:
	if stage > _stage:
		_shake = 0.12
	_stage = stage
	_broken = broken
	modulate = Color.WHITE.lerp(Color(0.7, 0.6, 0.55), stage)
	queue_redraw()


func _process(delta: float) -> void:
	if _broken:
		_broken_for += delta
		queue_redraw()
	if _shake > 0.0:
		_shake -= delta
		position.x = SHAKE if int(_shake * 60.0) % 2 == 0 and _shake > 0.0 else 0.0


func _frame() -> int:
	if _broken:
		return mini(3 + int(_broken_for * break_fps), frames - 1)
	return mini(int(_stage * 3.0), 2)


func _draw() -> void:
	if strip == null:
		return
	var w := strip.get_width() / float(frames)
	draw_texture_rect_region(strip, Rect2(at.x, at.y, w, strip.get_height()),
		Rect2(w * _frame(), 0.0, w, strip.get_height()))
