class_name EnemyCopter
extends EnemyFlyer
## 2-E Copter：会飞的那一种，但**不开枪，往下扔炸弹**——和 F 一样用现成的手雷。
##
## 飞行、巡逻、跟随全走 `EnemyFlyer`；`bullet_scene` 留空所以基类那套射击不开火。
## 炸弹就是敌人的手雷（`enemy_grenade.tscn`）：往正下方松手、不加上抛，所以它是直着掉下去的，
## 落地弹一下、再碰到就炸，规则和玩家的手雷完全一样。
##
## **炸弹在动作的第 3 帧脱钩**（`RELEASE_FRAME`），不是按下去就出手：素材里那两帧是机身下沉、松开挂钩，
## 炸弹从机腹离开的位置正好对得上。

@export_group("Bombs")
## 留空表示不扔（那样它就只是飞来飞去）。
@export var bomb_scene: PackedScene
## 两颗之间至少隔多久。
@export var drop_interval := 2.0
## 松手点（相对身体中心；朝左时 x 取反，不过它是从机腹正下方掉的，x 本来就是 0）。
@export var bomb_offset := Vector2(0, 10)
@export var drop_event := &"grenade_throw"

## 动作的第几帧脱钩，以及一次性动作多少帧一秒（**要和 `EnemySpriteAppearance.ONCE_FPS` 对得上**）。
const RELEASE_FRAME := 2
const RELEASE_FPS := 12.0
const RELEASE_DELAY := RELEASE_FRAME / RELEASE_FPS

var _drop_timer := 0.0
## 起手了还剩多久脱钩；<= 0 表示没在扔。
var _release_left := 0.0


func _physics_process(delta: float) -> void:
	super(delta)
	_update_drop(delta)


func _update_drop(delta: float) -> void:
	_drop_timer -= delta
	if _release_left > 0.0:
		_release_left -= delta
		if _release_left <= 0.0:
			_release()
		return
	if bomb_scene == null or _drop_timer > 0.0 or drop_target() == null:
		return
	_drop_timer = drop_interval
	_release_left = RELEASE_DELAY
	_visual.fire()


## 正下方（水平 below_width 以内）、看得见的玩家；否则 null。和基类开火的判断是同一条。
func drop_target() -> Node2D:
	var target := find_target()
	if target == null or absf(target.global_position.x - global_position.x) > below_width:
		return null
	return target


func _release() -> void:
	launch_projectile(bomb_scene, bomb_offset, Vector2.DOWN)
	GameEvents.report(drop_event, self)
