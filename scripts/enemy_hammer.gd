class_name EnemyHammer
extends EnemyWalker
## 2-D Hammer：履带机器人，巡逻兵的一种，但**不开枪**——走到跟前抡锤砸。
##
## 和 F 只扔手雷是同一个做法：巡逻、转身、接触伤害全走基类，`bullet_scene` 留空所以基类那套射击不开火，
## 自己只管「够得着就站定抡一下」。
##
## **伤害卡在抡到底那一帧**（`HIT_FRAME`），不是按下去就扣血：
## 画面上锤子还举在半空人就掉血的话，玩家没法从动作判断该什么时候躲。
## 抡的这段时间它站着不动，所以躲开的办法是退出锤子够得着的范围，或者跳过它。

@export_group("Charge")
## 看见玩家就**转过去冲**（巡逻兵本来只打正前方、不回头）。
## 比玩家走路（180）慢，和 D 一个道理：走开追不上，它只能逼你且战且退。
@export var charge_speed := 140.0
## 隔多高就不追了（它只会平地抡锤，爬不上平台）。
@export var charge_height := 48.0

@export_group("Hammer")
## 玩家在正前方这个水平距离以内就抡。
@export var smash_range := 44.0
## 高度差超过这么多就够不着（锤子是横着扫出去的）。
@export var smash_height := 28.0
## 两次抡之间至少隔多久。
@export var smash_interval := 1.8
@export var smash_damage := 42
## 锤头落点（相对身体中心，朝右时；朝左 x 取反）。
@export var smash_offset := Vector2(28, 8)
## 锤头周围这个半径里的玩家挨打。
@export var smash_radius := 22.0
@export var smash_event := &"hammer_smash"

## 抡到第几帧砸到地上，以及一次性动作是多少帧一秒。
## **必须和 `EnemySpriteAppearance.ONCE_FPS` 对得上**：画面上锤子落地那一刻才是扣血那一刻。
const HIT_FRAME := 5
const SWING_FPS := 12.0
## 从起手到砸中隔多久。
const HIT_DELAY := HIT_FRAME / SWING_FPS

## 正在冲向谁，没有就是 null。
var _hunted: Node2D = null

var _smash_timer := 0.0
## 抡到一半还剩多久砸中；<= 0 表示没在抡。
var _swing_left := 0.0


func _physics_process(delta: float) -> void:
	# **抡的时候不换目标也不转身**：抡到一半还跟着人转的话，起手之后躲开就没意义了
	_hunted = null if is_swinging() else hunt_target()
	if _hunted != null:
		var ahead := signi(_hunted.global_position.x - global_position.x)
		if ahead != 0 and ahead != facing:
			facing = ahead
			_apply_facing()
	super(delta)
	_update_smash(delta)


## 这一帧走多快：冲的时候快，巡逻的时候还是慢悠悠。
func walk_speed() -> float:
	return charge_speed if _hunted != null else move_speed


## 冲的时候不按巡逻规则掉头——朝向那会儿是冲着人的。
func patrolling() -> bool:
	return _hunted == null


## 正在冲向谁（测试用）。
func is_charging() -> bool:
	return _hunted != null


## 够得着、看得见、高度也差不多的玩家。**不分前后**——它要转过去冲。
## 「够得着」用 `within_reach`，所以在屏幕里的玩家它一定有反应（见 CLAUDE.md 的「视野对等」）。
func hunt_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if not within_reach(absf(offset.x)) or absf(offset.y) > charge_height:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null


## 够得着就站定抡，够不着就接着巡逻走近点（和 F 一个道理：它手上没枪，基类那套「交火」判断不适用）。
func is_engaged(_target: Node2D) -> bool:
	return _swing_left > 0.0 or smash_target() != null


func is_swinging() -> bool:
	return _swing_left > 0.0


func _update_smash(delta: float) -> void:
	_smash_timer -= delta
	if _swing_left > 0.0:
		_swing_left -= delta
		if _swing_left <= 0.0:
			_land_the_blow()
		return
	if _smash_timer > 0.0 or smash_target() == null:
		return
	_smash_timer = smash_interval
	_swing_left = HIT_DELAY
	_visual.fire()
	GameEvents.report(smash_event, self)


## 正前方、够得着、并且看得见的玩家；否则返回 null。和巡逻兵开枪一样只打正前方。
func smash_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if signi(offset.x) != facing and not is_zero_approx(offset.x):
			continue
		if absf(offset.x) > smash_range or absf(offset.y) > smash_height:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null


## 锤子落地：这一刻还站在锤头周围的才挨打——起手之后躲开就躲掉了。
func _land_the_blow() -> void:
	var at := smash_point()
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= smash_radius:
			player.take_damage(roundi(smash_damage * Stage.damage_scale()), at, self)


func smash_point() -> Vector2:
	return body_center() + Vector2(smash_offset.x * facing, smash_offset.y)
