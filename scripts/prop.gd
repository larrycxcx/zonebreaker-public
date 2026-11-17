class_name Prop
extends Sprite2D
## 关卡里的装饰：长椅、树、石头、草丛、喷泉这些。
##
## **纯显示**：整棵树里不许有碰撞体，也不参与任何判定——和特效是同一条规矩。
## 关卡里它们挂在 `Props` 节点下，**画在所有东西后面**（背景之后、地形之前），
## 所以再密也不会挡住敌人、子弹和地形；`Props` 整个删掉游戏照常跑。
##
## 贴图的**左下角对准节点位置**（`centered = false` 再往上挪一个身高），
## 摆的时候直接给「站在哪个面上」就行。
##
## 多帧的是横着排成一条的动画（喷泉 288×72 = 4 帧 × 72），按 `region_rect` 逐帧播。

## 贴图的路径。**关卡场景里存路径、不直接引用贴图**：装饰是第三方素材，公开版里没有，
## 直接引用的话整个关卡场景都加载不了；存路径的话缺了就是不画（`_ready` 里加载，没有就空着）。
@export_file("*.png") var texture_path := ""
## 贴图左下角对准节点位置（装饰的摆法）。false = 居中（贴花的摆法：编号牌上的数字贴在圆盘正中）。
@export var bottom_left := true
## 贴图里横着排了几帧。1 = 静止的，不走 `_process`。
@export var frames := 1
## 多帧时一秒播几帧。
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
	# 位置写的是「贴图底边落在哪儿」，所以整张往上挪一个身高
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
