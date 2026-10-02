class_name ScreenLight
extends ColorRect
## 素材包的**光照层**（`SkinPack.lighting`）：一整块盖住画面的方块，着色器把一张彩色光斑
## 按 overlay 方式混到它**底下已经画好的东西**上（酒吧街宣传图那种粉 / 青霓虹就是这么来的）。
##
## **纯显示**：没有碰撞、不接鼠标。关卡把它插在 `Level` 后面、`Enemies` 前面
## （`main.gd._add_lighting()`），所以背景、楼面、装饰、地形被染色，
## **敌人、玩家、子弹、特效画在它上面、保持原色**——染了色的人在霓虹里就看不清了。
##
## 它是世界里的一个节点，每帧挪到摄像机看着的那块上；四边多留 `MARGIN`，
## 摄像机移动和屏幕抖动时边上不会漏出一条没染色的。

const MARGIN := 64.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	global_position = view.position - Vector2(MARGIN, MARGIN)
	size = view.size + Vector2(MARGIN, MARGIN) * 2.0
	var shader := material as ShaderMaterial
	if shader != null:
		shader.set_shader_parameter(&"view_origin", view.position)
