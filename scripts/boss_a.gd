class_name BossA
extends Boss
## Boss A：体型大、会跳、不会趴下，主要靠射击攻击；不主动追击，碰到玩家照样造成接触伤害（基类规则）。
##
## - 移动：在以出生点为中心的 ±roam_range 地盘里「找开火位置」，由**和玩家的水平距离**决定往哪走：
##   贴得太近（< close_range）就边退边打，离得太远（> far_range）就压进射程，不远不近就随机来回游走。
##   **永远不走出自己的地盘**，所以它不会像敌人 D 那样追着玩家跑（追击是 D 的定位，它靠射击）。
##   另外隔一段随机时间跳一下。
## - 射击：朝玩家方向取最接近的 8 方向之一（水平、斜上、正上、斜下、正下），走动中、空中都照样开火。
##   水平子弹的出膛高度和普通敌人一样离地 7px（趴下的玩家能躲开站着射出的水平子弹，规则不变）。
## - 抢高处：玩家趴下时，它站在地上打的水平子弹会从玩家头顶飞过（高度规则），这时它会跳上 high_ground 指定的平台，
##   居高临下斜着往下打。玩家一站起来它就不想占着高处了，走位规则会把它带到平台边沿、自己掉下来。
##   平时（玩家没趴下）它**不会**跳上那块平台：在平台正下方时随机跳跃会跳过这一次。
## - 躲手雷：已经落过地（Grenade.landed）、正贴着地面弹跳的手雷进入 dodge_distance 时，起跳并朝远离它的方向移动；
##   还在空中飞、没落过地的手雷不躲（可以直接砸中它）。

@export_group("Movement")
## 走动速度，以及地盘半径（以出生点为中心，走到边界就折回，不会追出去）。
@export var roam_speed := 90.0
@export var roam_range := 160.0
## 玩家近到这个距离以内就后撤（边退边打），远过 far_range 就压进射程，中间随机游走。
@export var close_range := 100.0
@export var far_range := 280.0
## 后撤时走多快。比玩家走路（90）慢，所以玩家想贴上来总是贴得到，只是要吃它的近距离火力。
@export var back_off_speed := 120.0
## 多久随机换一次走动方向（秒，在这两个值之间取）。
@export var turn_time_min := 1.0
@export var turn_time_max := 2.5
@export var jump_velocity := -640.0
## 两次跳跃之间隔多久（秒，在这两个值之间取）。
@export var jump_interval_min := 1.5
@export var jump_interval_max := 3.0

@export_group("High ground")
## 玩家趴下时跳上去打斜下的平台（在关卡里指定）。留空就没有这个行为。
@export var high_ground: NodePath
## 玩家趴下多久之后才决定跳上去（秒），给玩家留反应时间。
@export var high_ground_delay := 0.6

@export_group("Grenade dodge")
## 落地的手雷离自己多近（水平）时开始躲。手雷爆炸半径 28 + 自己半个身宽，再留点余量。
@export var dodge_distance := 112.0
## 躲的时候水平移动多快。
@export var dodge_speed := 220.0

## 水平射击的出膛点（相对身体中心，朝右时）：y = 碰撞体底边(16) - 7，和普通敌人离地 7px 一致。
const LEVEL_MUZZLE := Vector2(30, 10)
## 其它方向的出膛点：身体中心 + 方向 × 这个伸出量（x、y 分开，适配竖长的身体）。
const MUZZLE_REACH := Vector2(28, 40)
## 碰撞体半高（原点到脚底）。
const HALF_HEIGHT := 32.0

## 当前瞄准的方向（8 方向之一），占位美术的枪管按它转。
var aim_direction := Vector2.LEFT
## 这一帧是否在躲手雷（测试读）。
var is_dodging := false
## 这一帧是否想待在高处（测试读）。
var wants_high_ground := false

var _home := Vector2.ZERO
var _roam_dir := -1
var _turn_timer := 0.0
var _jump_timer := 0.0
## 玩家已经趴了多久（基类里的 _prone_timer 是敌人自己趴下用的，别重名）。
var _player_prone_timer := 0.0

@onready var _high_ground: Platform = get_node_or_null(high_ground) as Platform

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
	var target := find_target()
	_update_high_ground_wish(delta, target)
	# 优先级：躲手雷 > 抢高处 > 平时走动。
	if is_dodging:
		_dodge(threat)
	elif wants_high_ground:
		_take_high_ground()
	else:
		_reposition(delta, target)
	move_and_slide()
	if is_on_wall():
		_roam_dir = -_roam_dir

	if target != null:
		# 瞄身体中心：玩家趴下时中心更低，斜下才打得准。
		var point: Vector2 = target.body_center() if target is Player else target.global_position
		aim_direction = snap_direction(point - global_position)
		if aim_direction.x != 0.0:
			facing = signi(aim_direction.x)
	elif velocity.x != 0.0:
		facing = signi(velocity.x)
		aim_direction = Vector2(facing, 0)
	_show_facing()
	try_shoot(delta, target)


## 按和玩家的距离找开火位置：太近后撤、太远压上、不远不近随机游走；越过地盘边界就折回来。
func _reposition(delta: float, target: Node2D) -> void:
	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_roam_dir = -_roam_dir
		_turn_timer = randf_range(turn_time_min, turn_time_max)
	var speed := roam_speed
	var dir := float(_roam_dir)
	if target != null:
		var offset := target.global_position.x - global_position.x
		var toward := signf(offset)
		if toward == 0.0:
			toward = float(facing)
		if absf(offset) < close_range:
			dir = -toward
			speed = back_off_speed
		elif absf(offset) > far_range:
			dir = toward
	# 地盘边界优先于上面所有的判断：宁可被玩家贴脸，也不追出去。
	if global_position.x > _home.x + roam_range:
		dir = -1.0
		speed = roam_speed
	elif global_position.x < _home.x - roam_range:
		dir = 1.0
		speed = roam_speed
	_roam_dir = signi(dir)
	velocity.x = speed * dir
	if is_on_floor():
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			# 平时不跳上高处那块平台：只有玩家趴下时才上去。
			if _would_land_on_high_ground():
				# 这一跳会落到平台上，先不跳；过一小会儿再试，而不是等满整个间隔
				#（否则它在平台附近来回走时会很久都不跳一下）。
				_jump_timer = 0.2
			else:
				velocity.y = jump_velocity
				_jump_timer = randf_range(jump_interval_min, jump_interval_max)


## 玩家趴下、并且自己还在地面上打不着它时，就想上高处去。玩家站起来就不想了。
func _update_high_ground_wish(delta: float, target: Node2D) -> void:
	var player := target as Player
	if _high_ground == null or player == null or not player.is_crouching:
		_player_prone_timer = 0.0
		wants_high_ground = false
		return
	_player_prone_timer += delta
	wants_high_ground = _player_prone_timer >= high_ground_delay


## 走到平台下方再起跳；已经在上面了就站定开枪。
func _take_high_ground() -> void:
	if on_high_ground():
		velocity.x = 0.0
		return
	var center := _high_ground.global_position.x + _high_ground.size.x / 2.0
	velocity.x = roam_speed * signf(center - global_position.x)
	if is_on_floor() and _under_high_ground():
		velocity.y = jump_velocity


## 是不是正站在那块平台上（高度和水平位置都要对上：光看高度的话站在别的平台上也会算进来）。
func on_high_ground() -> bool:
	if _high_ground == null or not is_on_floor():
		return false
	if global_position.y + HALF_HEIGHT > _high_ground.global_position.y + 4.0:
		return false
	return global_position.x > _high_ground.global_position.x - 4.0 		and global_position.x < _high_ground.global_position.x + _high_ground.size.x + 4.0


## 这一跳会不会落到高处那块平台上（按当前水平速度算落点）。
## 不能只看「现在是不是在平台正下方」：空中还会横着飘一段，在边上起跳照样会落上去，
## 而在平台下方朝外走时起跳反而落在地上。范围划太宽的话它几乎就不跳了。
func _would_land_on_high_ground() -> bool:
	if _high_ground == null or on_high_ground():
		return false
	var air_time := 2.0 * absf(jump_velocity) / gravity
	var landing := global_position.x + velocity.x * air_time
	var left := _high_ground.global_position.x
	var right := left + _high_ground.size.x
	return landing > left - 8.0 and landing < right + 8.0


## 身体在不在平台的正下方（起跳上得去的位置）。
func _under_high_ground() -> bool:
	if _high_ground == null or on_high_ground():
		return false
	var left := _high_ground.global_position.x
	var right := left + _high_ground.size.x
	return global_position.x > left + 8.0 and global_position.x < right - 8.0


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


## 占位美术：身体朝向 + 枪管转到瞄准方向（枪管由基类按 gun_visual 转，方向取 shoot_direction()）。
func _show_facing() -> void:
	_apply_visual_facing()
