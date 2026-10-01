class_name EnemyLunger
extends EnemyWalker
## 3-A 刀客：巡逻兵的一种，但**不开枪**——看见正前方的玩家就**先定住蓄一下，再急冲一段去刺**。
##
## 和已有的那几种近身都不一样：
## - 冲撞（D、2-B）是**匀速贴上来**，你走开就能拉开；
## - 抡锤（2-D）是**走到跟前站定再抡**，起手之后退开就躲掉了；
## - 这个是**一次爆发**：冲的时候比玩家走路快得多，跑是跑不掉的，
##   **躲法是在它蓄力那一下跳开**（`lunge_windup` 就是留给玩家的那段时间）。
##
## 伤害走的是基类那套接触伤害——它冲过来撞到你就是挨刀，不另算一份。

## 蓄力和冲刺这两段各自的状态。
enum Dash { NONE, WINDUP, GO, REST }

@export_group("Lunge")
## 正前方这个距离以内就起手。
@export var lunge_range := 120.0
## 高度差超过这么多就够不着（它不会跳）。
@export var lunge_height := 32.0
## **定住蓄力多久**。这是留给玩家跳开的时间，调小了就变成没法躲。
@export var lunge_windup := 0.45
## 冲的速度和时长。速度比玩家走路（180）快得多——跑不掉，只能跳。
@export var lunge_speed := 300.0
@export var lunge_time := 0.3
## 冲完歇多久才会再来一次。
@export var lunge_rest := 1.2
## 起手时报一声，和 D 发现玩家共用一个音效（意思一样：它盯上你了）。
@export var lunge_event := &"chaser_alert"

var _dash := Dash.NONE
var _left := 0.0


func _physics_process(delta: float) -> void:
	# **这里不用管朝向**：`lunge_target()` 只认正前方的玩家，所以起手时朝向本来就是对的；
	# 起手之后它认准那个方向冲出去，转向完全由巡逻决定（和别的巡逻兵一样）。
	super(delta)
	_update_dash(delta)


## 正在冲（测试和外观都要问）。
func is_dashing() -> bool:
	return _dash == Dash.GO


func is_winding_up() -> bool:
	return _dash == Dash.WINDUP


## 蓄力时站定、冲的时候全速、别的时候照常巡逻。
func walk_speed() -> float:
	return lunge_speed if _dash == Dash.GO else move_speed


func patrolling() -> bool:
	return _dash == Dash.NONE


## 蓄力那一下定住不动（基类按这个把速度清零）。
func is_engaged(_target: Node2D) -> bool:
	return _dash == Dash.WINDUP or _dash == Dash.REST


func _update_dash(delta: float) -> void:
	if _dash == Dash.NONE:
		if lunge_target() != null:
			_dash = Dash.WINDUP
			_left = lunge_windup
			GameEvents.report(lunge_event, self)
		return
	_left -= delta
	if _left > 0.0:
		return
	match _dash:
		Dash.WINDUP:
			_dash = Dash.GO
			_left = lunge_time
			_visual.fire()      # 刺出去那一下
		Dash.GO:
			_dash = Dash.REST
			_left = lunge_rest
		Dash.REST:
			_dash = Dash.NONE


## 正前方、够得着、高度也差不多、并且看得见的玩家；否则 null。
## 「够得着」走 `within_reach`，所以在屏幕里的玩家它一定有反应（见 CLAUDE.md 的「视野对等」）。
func lunge_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if signi(offset.x) != facing and not is_zero_approx(offset.x):
			continue
		if absf(offset.x) > lunge_range and not is_partly_on_screen():
			continue
		if absf(offset.x) > lunge_range * 2.0 or absf(offset.y) > lunge_height:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null
