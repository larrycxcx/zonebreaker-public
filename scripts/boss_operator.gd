class_name BossOperator
extends Boss
## Boss 2「机械操作员」：一个在空中飘的铁球，底下能伸出一条机械臂。
##
## **两种打法轮流来**（这是它和 Boss A 最大的区别——那个只会打扇形）：
## 1. **伸臂**：正下方有人时缆绳放下去，爪子到底那一刻合拢，抓中就扣血。
##    伸出去要时间、爪子只在正下方那一小块，所以**跑开就躲掉了**——和锤子兵同一条道理。
## 2. **子弹**：手臂收着的时候从球底的舱口打一串，**全都沿同一条线**（「单向」），
##    不像 Boss A 那样铺一个扇形。躲法也不同：那个要站进扇形的空隙，这个是横向闪开。
##
## 飞行不受重力（场景里 `motion_mode` 是 floating），在出生点周围一块矩形地盘里按八个方向飘。
## **不追出地盘**：追击是敌人 D 的定位；它靠居高临下压制，玩家要靠平台跳上来打它。

@export_group("Movement")
## 地盘：以出生点为中心，横竖各多少像素。
@export var roam_range := Vector2(200.0, 88.0)
@export var roam_speed := 70.0
## 多久换一次方向。
@export var turn_time_min := 0.8
@export var turn_time_max := 1.8

@export_group("Arm")
## 缆绳最多放多长（从球底算起）。
@export var arm_max_length := 132.0
## 放下去和收回来的速度。
@export var arm_speed := 320.0
## 爪子合拢、抓一下要多久。
@export var arm_grab_time := 0.25
## 玩家的水平距离在这个范围内才算「在正下方」，值得伸手臂。
@export var arm_width := 36.0
## 爪子周围这个半径里的玩家挨抓。
@export var claw_radius := 22.0
@export var claw_damage := 46

@export_group("Volley")
## 两次攻击之间歇多久。
@export var attack_interval := 1.2

@export_group("Enraged")
## 血掉到这个比例以下就进第二阶段：飞得更快，子弹从一条线变成一把扇形。
## **第一阶段只会一条线，站开就躲掉了**——血过半之后再不变招，后半场就是站着磨（试玩反馈）。
@export_range(0.0, 1.0) var enrage_below := 0.5
## 第二阶段的飞行速度倍率。
@export var enrage_speed_scale := 1.5
## 第二阶段一发变几发，每发隔多少度。
@export var enrage_fan_count := 3
@export var enrage_fan_spread := 18.0
## 第二阶段「出手更快」的倍率：开火间隔、两次攻击之间的停顿都乘它，缆绳放收的速度除以它。
## **机械臂也要跟着变**——玩家多半站在它正下方，那时它一直在用手臂，
## 只改飞行速度和子弹扇形的话，二阶段在最常见的位置上根本看不出来（2026-09 试玩反馈）。
@export var enrage_rush := 0.7

## 缆绳从球上哪儿出来、子弹从哪儿打出去（相对身体原点）。两个是同一个口。
const POD_MUZZLE := Vector2(0, 30)

## 手臂的四个状态：收着 / 正在放 / 爪子合拢抓一下 / 正在收。
enum Arm {IN, OUT, GRAB, BACK}

var _arm := Arm.IN
var _arm_length := 0.0
## 这一次要放到多长：**放到玩家所在的高度就停**，不是一律放到最长。
## 一律放最长的话，人站得高一点爪子就从他脑袋边上插过去了。
var _arm_goal := 0.0
var _grab_left := 0.0
## 下一次轮到手臂还是子弹。
var _arm_next := true
## 正在打一轮子弹（用来判断「这一轮打完了」）。
var _volleying := false
var _rest := 0.0
## 第二阶段这一轮已经打出去几发（用来把扇形铺开）。
var _fan_index := 0
## 进没进第二阶段。**是个闩**，不是每帧按血量重算——换挡只发生一次，才报得出那一下。
var _enraged := false

var _home := Vector2.ZERO
var _heading := Vector2.ZERO
var _turn_left := 0.0


func _ready() -> void:
	super()
	_home = global_position
	_pick_heading()


func _boss_process(delta: float) -> void:
	# **伸着手臂的时候不飘**：缆绳是吊着的，一边放一边飘的话爪子会落到瞄好的位置以外，
	# 玩家明明没动也可能被抓不中（或者站着没动反而被抓中）。停住也让这一下看得清、躲得掉。
	if _arm == Arm.IN:
		_drift(delta)
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_report_motion()
	if _arm != Arm.IN:
		_update_arm(delta)
		return
	_rest -= delta
	var target := find_target()
	if target == null or _rest > 0.0:
		return
	var below := arm_target()
	if _arm_next and below != null:
		_arm = Arm.OUT
		_arm_goal = clampf(below.call(&"body_center").y - global_position.y - POD_MUZZLE.y,
			0.0, arm_max_length)
		_arm_next = false
		return
	# 正下方没人就不空等，改打子弹（下一轮照样先轮到手臂）
	try_shoot(delta, target)
	if is_firing_burst():
		_volleying = true
	elif _volleying:
		_volleying = false
		_arm_next = true
		_rest = attack_interval


func arm_length() -> float:
	return _arm_length


func arm_state() -> Arm:
	return _arm


## 正下方（水平 arm_width 以内）、在下面、够得着的玩家；否则 null。
func arm_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) > arm_width or offset.y <= 0.0:
			continue
		if offset.y - POD_MUZZLE.y > arm_max_length:
			continue
		return player
	return null


## 爪子现在在哪儿（世界坐标）。
func claw_position() -> Vector2:
	return global_position + POD_MUZZLE + Vector2(0.0, _arm_length)


func _update_arm(delta: float) -> void:
	match _arm:
		Arm.OUT:
			_arm_length = minf(_arm_length + arm_speed * delta, _arm_goal)
			if is_equal_approx(_arm_length, _arm_goal):
				_arm = Arm.GRAB
				_grab_left = arm_grab_time
				_snap_shut()
		Arm.GRAB:
			_grab_left -= delta
			if _grab_left <= 0.0:
				_arm = Arm.BACK
		Arm.BACK:
			_arm_length = maxf(_arm_length - arm_speed * delta, 0.0)
			if _arm_length <= 0.0:
				_arm = Arm.IN
				_rest = attack_interval
	_show_arm()


## 爪子到底、合拢的那一刻才扣血：放缆绳要时间，这段时间玩家看得见也跑得开。
func _snap_shut() -> void:
	var at := claw_position()
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= claw_radius:
			player.take_damage(roundi(claw_damage * Stage.damage_scale()), at, self)


func _show_arm() -> void:
	if _visual.has_method(&"show_arm"):
		_visual.call(&"show_arm", _arm_length, _arm == Arm.GRAB)


## 在地盘里按八个方向飘，撞到地盘边就把那个分量反过来。
func _drift(delta: float) -> void:
	_turn_left -= delta
	if _turn_left <= 0.0:
		_pick_heading()
	var offset := global_position - _home
	if absf(offset.x) > roam_range.x and signf(offset.x) == signf(_heading.x):
		_heading.x = -_heading.x
	if absf(offset.y) > roam_range.y and signf(offset.y) == signf(_heading.y):
		_heading.y = -_heading.y
	velocity = _heading * roam_speed * (enrage_speed_scale if is_enraged() else 1.0)
	if not is_zero_approx(_heading.x):
		facing = signi(_heading.x)
		_apply_visual_facing()


## 八个方向里随便挑一个（不含原地不动）。
func _pick_heading() -> void:
	_turn_left = randf_range(turn_time_min, turn_time_max)
	var pick := randi_range(0, 7)
	var angle := pick * TAU / 8.0
	_heading = Vector2(snappedf(cos(angle), 0.001), snappedf(sin(angle), 0.001)).normalized()


## 进没进第二阶段。
func is_enraged() -> bool:
	return _enraged


## 掉到半血以下就换挡。**报一个事件**（声音 + 屏幕抖一下）——
## 不报的话玩家根本不知道它变了：飞快一点、子弹多两发，都不够显眼（2026-09 试玩反馈）。
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= float(max_health) * enrage_below:
		_enraged = true
		fire_interval *= enrage_rush
		attack_interval *= enrage_rush
		arm_speed /= enrage_rush
		GameEvents.report(&"boss_enrage", self)


## 一轮子弹全沿同一条线（「单向」）：基类在一轮开始时调这个锁一次方向，剩下的沿用。
## **这儿顺手把扇形的计数归零**——它每轮只被调一次，正好是「一轮开始了」那一刻。
func shoot_direction() -> Vector2:
	_fan_index = 0
	var target := find_target()
	if target == null:
		return Vector2(facing, 0.0)
	return (target.call(&"body_center") - _muzzle_position()).normalized()


## 这一发朝哪儿飞。第一阶段就是锁定的那条线；**第二阶段每一发各自偏开一点**，
## 一轮打出一把扇形，躲法从「横向闪开」变成「站进两发之间的空隙」。
func burst_direction() -> Vector2:
	if not is_enraged():
		return super()
	var middle := (enrage_fan_count - 1) / 2.0
	var step: float = (_fan_index % enrage_fan_count) - middle
	_fan_index += 1
	return super().rotated(deg_to_rad(step * enrage_fan_spread))


## 子弹和缆绳从同一个口出去。
func _muzzle_position() -> Vector2:
	return global_position + POD_MUZZLE


## 它不分水平 / 斜射：够得着就打，方向由 `shoot_direction()` 现算。
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if within_reach(global_position.distance_to(target.global_position)) else -1
