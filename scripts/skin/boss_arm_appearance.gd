class_name BossArmAppearance
extends EnemySpriteAppearance
## 工业区 Boss「机械操作员」的外观：铁球走基类那套贴图，另外画一条**能伸到任意长度**的机械臂。
##
## 素材里 `Up-Down` 那 6 帧只有 6 档缆绳长度，而伸多长是玩法说了算的，
## 所以拆成「缆绳的一行」竖着平铺 + 「爪子」贴在末端。爪子有张开和合拢两张，抓下去那一刻换成合拢的。
##
## 和别的外观一样：**玩法只调 `show_arm()`**，画成什么样、缆绳多粗、爪子长什么样都是这儿的事。
## 占位方块那套没有这个方法，所以默认皮肤下就是不画——规则一点不变。

## 缆绳（一行，竖着平铺）和两张爪子。
@export var cable: Texture2D
@export var claw_open: Texture2D
@export var claw_shut: Texture2D
## 缆绳从球上的哪儿伸出来（相对身体原点）。
@export var arm_origin := Vector2(0, 30)

## 现在伸出去多长（<= 0 表示收着、不画），以及爪子合上了没有。
var _length := 0.0
var _shut := false


## 伸出去 length 像素；length <= 0 表示收回去。
func show_arm(length: float, shut := false) -> void:
	if is_equal_approx(length, _length) and shut == _shut:
		return
	_length = length
	_shut = shut
	queue_redraw()


func _draw() -> void:
	if cable == null or _length <= 0.0:
		return
	var width := float(cable.get_width())
	var rows := roundf(_length)
	# 一行图竖着平铺（tile = true），所以伸多长都不会被拉糊
	draw_texture_rect(cable, Rect2(arm_origin.x - width / 2.0, arm_origin.y, width, rows), true)
	var head := claw_shut if _shut and claw_shut != null else claw_open
	if head != null:
		draw_texture(head, Vector2(arm_origin.x - head.get_width() / 2.0, arm_origin.y + rows))
