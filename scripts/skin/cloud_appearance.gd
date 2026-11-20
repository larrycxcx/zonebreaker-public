class_name CloudAppearance
extends Appearance
## 毒雾的外观：玩法告诉它「散到几成了」（`show_progress(0..1)`），它就画到那一帧——
## 不自己按时间播，画面和判定是同一个进度。
## 有贴图（素材包的 `Acid2`，一团慢慢散开的毒雾，一帧正方形）就按进度挑帧，中心对准节点原点；
## 没有（默认皮肤）就画一个半透明的圈，越散越淡。

@export var strip: Texture2D
@export var frames := 6
@export var color := Color(0.35, 0.85, 0.45, 0.55)
## 没贴图时圈的半径（跟玩法的判定半径一样大）。
@export var radius := 24.0

var _progress := 0.0


func _ready() -> void:
	pass


func show_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func current_frame() -> int:
	return mini(int(_progress * frames), frames - 1)


func _draw() -> void:
	if strip == null:
		var faded := color
		faded.a *= 1.0 - _progress * 0.7
		draw_circle(Vector2.ZERO, radius, faded)
		return
	var size := float(strip.get_height())
	draw_texture_rect_region(strip, Rect2(-size / 2.0, -size / 2.0, size, size),
		Rect2(size * current_frame(), 0.0, size, size))
