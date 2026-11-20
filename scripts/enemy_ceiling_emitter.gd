class_name EnemyCeilingEmitter
extends Enemy
## 第五关的 5-F：**倒挂在天花板上的毒气发射器**，一动不动。玩家走到它下方（左右 `trigger_width` 以内、
## 往下 `trigger_depth` 以内、看得见）就开始：**先充能**（播攻击那几帧，面板在变——预警），
## `charge_time` 秒后**滴一滴毒液**（`PoisonDrip`），落地炸成一团毒雾（中毒），然后歇 `cooldown` 秒。
## 躲法：看见它充能就加快走过去，或者先把它打掉（得往上 / 斜上打）。
## 不受重力（场景里 floating），原点是发射器的中心，吊架顶边（天花板）在原点上面 20（`MOUNT`）。

@export_group("Drip")
@export var drip_scene: PackedScene = preload("res://scenes/poison_drip.tscn")
@export var trigger_width := 40.0
@export var trigger_depth := 280.0
@export var charge_time := 0.6
@export var cooldown := 2.2
## 毒液从哪儿滴出来（相对原点）：发射器底下。
@export var drip_offset := Vector2(0, 14)
@export var charge_event := &"chaser_alert"

## 吊架顶边在原点上面多少（摆位用：顶边贴着天花板）。
const MOUNT := 20.0

var _charge := 0.0
var _rest := 0.0


func is_charging() -> bool:
	return _charge > 0.0


func _physics_process(delta: float) -> void:
	_rest = maxf(0.0, _rest - delta)
	if _charge > 0.0:
		_charge -= delta
		if _charge <= 0.0:
			_drip()
		return
	if _rest <= 0.0 and drip_target() != null:
		_charge = charge_time
		if _visual != null:
			_visual.fire()
		GameEvents.report(charge_event, self)


## 正下方的玩家（左右够近、往下够得着、中间没被实心挡住），没有就 null。
func drip_target() -> Player:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) <= trigger_width and offset.y > 0.0 and offset.y <= trigger_depth \
				and has_line_of_sight(player.body_center()):
			return player
	return null


func _drip() -> void:
	_rest = cooldown
	launch_projectile(drip_scene, drip_offset, Vector2.DOWN)
