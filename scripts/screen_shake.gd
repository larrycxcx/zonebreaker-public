class_name ScreenShake
extends Camera2D
## 屏幕抖动：和 `Fx`、`Sfx` 一样是事件总线上的听众，按事件名决定抖多狠。
##
## 只改摄像机的 `offset`，不碰跟随玩家的位置，也不碰关卡边界，所以抖完自动回到原位。
## 每帧朝一个随机方向偏移固定的幅度，再按整像素取整——320×180 的像素画面，半个像素的抖动只会让画面发糊。

## 各事件抖多少像素。玩家自己开枪只抖一点点，爆炸和终极武器最狠。
const SHAKES := {
	&"player_shoot": 0.6,
	&"player_hurt": 2.0,
	&"player_death": 3.0,
	&"enemy_death": 1.0,
	&"explosion": 3.0,
	&"boss_appear": 2.0,
	&"ultimate_start": 2.5,
	&"ultimate_blast": 4.0,
}

## 整体强度倍率：试玩觉得晃得难受就调小，设 0 就完全不抖。
@export var strength_scale := 1.0
## 每秒衰减多少像素（越大停得越快）。
@export var decay := 14.0

var _strength := 0.0


func _ready() -> void:
	# 终极武器发动时整棵树会暂停，那一下的抖动要照常看得见。
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.event_happened.connect(_on_event)


func _on_event(event: StringName, _source: Node) -> void:
	if SHAKES.has(event):
		shake(SHAKES[event])


## 抖 amount 像素。已经在抖更狠的就保持更狠的，别让小抖动打断大抖动。
func shake(amount: float) -> void:
	_strength = maxf(_strength, amount * strength_scale)


func _process(delta: float) -> void:
	if _strength <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_strength = move_toward(_strength, 0.0, decay * delta)
	# 方向随机、幅度固定：两个分量各自随机的话会有相当一部分帧取整成 (0, 0)，抖动会一帧一帧地漏。
	offset = (Vector2.from_angle(randf() * TAU) * _strength).round()
