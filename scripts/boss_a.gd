class_name BossA
extends Boss
## Boss A：体型大、会跳、不会趴下，主要靠射击攻击；不主动追击，碰到玩家照样造成接触伤害（基类规则）。
##
## - 移动：以出生点为中心在 ±roam_range 内来回走动（随机改变方向），隔一段随机时间跳一下。
##   走动和玩家在哪里无关，所以不会追过来；只有面朝方向跟着玩家转。
## - 射击：朝玩家方向取最接近的 8 方向之一（水平、斜上、正上、斜下、正下），走动中、空中都照样开火。
##   水平子弹的出膛高度和普通敌人一样离地 7px（趴下的玩家能躲开站着射出的水平子弹，规则不变）。
## - 躲手雷：已经落过地（Grenade.landed）、正贴着地面弹跳的手雷进入 dodge_distance 时，起跳并朝远离它的方向移动；
##   还在空中飞、没落过地的手雷不躲（可以直接砸中它）。

@export_group("Movement")
## 平时走动的速度和范围（以出生点为中心）。
@export var roam_speed := 35.0
@export var roam_range := 32.0
## 多久随机换一次走动方向（秒，在这两个值之间取）。
@export var turn_time_min := 1.0
@export var turn_time_max := 2.5
@export var jump_velocity := -320.0
## 两次跳跃之间隔多久（秒，在这两个值之间取）。
@export var jump_interval_min := 1.5
@export var jump_interval_max := 3.0

@export_group("Grenade dodge")
## 落地的手雷离自己多近（水平）时开始躲。手雷爆炸半径 28 + 自己半个身宽，再留点余量。
@export var dodge_distance := 56.0
## 躲的时候水平移动多快。
@export var dodge_speed := 110.0

## 水平射击的出膛点（相对身体中心，朝右时）：y = 碰撞体底边(16) - 7，和普通敌人离地 7px 一致。
const LEVEL_MUZZLE := Vector2(15, 9)
## 其它方向的出膛点：身体中心 + 方向 × 这个伸出量（x、y 分开，适配竖长的身体）。
const MUZZLE_REACH := Vector2(14, 20)

## 当前瞄准的方向（8 方向之一），占位美术的枪管按它转。
var aim_direction := Vector2.LEFT
## 这一帧是否在躲手雷（测试读）。
var is_dodging := false

var _home := Vector2.ZERO
var _roam_dir := -1
var _turn_timer := 0.0
var _jump_timer := 0.0

@onready var _gun: Control = $Visual/Gun


func _ready() -> void:
	super()
	_home = global_position
	_turn_timer = randf_range(turn_time_min, turn_time_max)
	_jump_timer = randf_range(jump_interval_min, jump_interval_max)


## 把一个偏移量取整到最接近的 8 方向（单位向量）。
static func snap_direction(offset: Vector2) -> Vector2:
	if offset == Vector2.ZERO:
		return Vector2.ZERO
	var step := PI / 4.0
	var angle := roundf(offset.angle() / step) * step
	var dir := Vector2.from_angle(angle)
	# 去掉浮点误差，让水平/竖直方向正好是 0。
	return Vector2(snappedf(dir.x, 0.0001), snappedf(dir.y, 0.0001)).normalized()


func _boss_process(delta: float) -> void:
	_apply_gravity(delta)
	var threat := _grenade_threat()
	is_dodging = threat != null
	if is_dodging:
		_dodge(threat)
	else:
		_roam(delta)
	move_and_slide()
	if is_on_wall():
		_roam_dir = -_roam_dir

	var target := find_target()
	if target != null:
		aim_direction = snap_direction(target.global_position - global_position)
		if aim_direction.x != 0.0:
			facing = signi(aim_direction.x)
	elif velocity.x != 0.0:
		facing = signi(velocity.x)
		aim_direction = Vector2(facing, 0)
	_show_facing()
	try_shoot(delta, target)


## 在出生点附近走来走去，隔一阵跳一下。
func _roam(delta: float) -> void:
	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_roam_dir = -_roam_dir
		_turn_timer = randf_range(turn_time_min, turn_time_max)
	if global_position.x > _home.x + roam_range:
		_roam_dir = -1
	elif global_position.x < _home.x - roam_range:
		_roam_dir = 1
	velocity.x = roam_speed * _roam_dir
	if is_on_floor():
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			velocity.y = jump_velocity
			_jump_timer = randf_range(jump_interval_min, jump_interval_max)


## 起跳并朝远离手雷的方向移动（靠墙退不了的时候，光靠起跳也能让身体离开爆炸范围）。
func _dodge(grenade: Grenade) -> void:
	var away := signf(global_position.x - grenade.global_position.x)
	if away == 0.0:
		away = -facing
	velocity.x = dodge_speed * away
	if is_on_floor():
		velocity.y = jump_velocity


## 离自己最近的一颗「落过地」的手雷（在 dodge_distance 内），没有返回 null。空中还没落地的手雷不算。
func _grenade_threat() -> Grenade:
	var nearest: Grenade = null
	var best := dodge_distance
	for node in get_tree().get_nodes_in_group(Grenade.GROUP):
		var grenade := node as Grenade
		if grenade == null or not grenade.landed or grenade.exploded:
			continue
		var distance := absf(grenade.global_position.x - global_position.x)
		if distance <= best:
			best = distance
			nearest = grenade
	return nearest


## 8 个方向都能打：射程内（直线距离）看得见就打。
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if global_position.distance_to(target.global_position) <= detect_range else -1


func shoot_direction() -> Vector2:
	return aim_direction


func _muzzle_position() -> Vector2:
	var d := _burst_direction
	if d.y == 0.0:
		return global_position + Vector2(LEVEL_MUZZLE.x * d.x, LEVEL_MUZZLE.y)
	return global_position + d * MUZZLE_REACH


## 占位美术：身体朝向 + 枪管转到瞄准方向（Visual 左右翻转，所以枪管按翻转后的本地方向转）。
func _show_facing() -> void:
	_visual.scale.x = facing
	_gun.rotation = Vector2(aim_direction.x * facing, aim_direction.y).angle()
