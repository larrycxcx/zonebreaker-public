class_name BossA
extends Boss
## Boss A：四条腿的导弹机甲。体型大、会跳、不会趴下，靠背上的导弹巢打扇形弹幕；不主动追击，
## 碰到玩家照样造成接触伤害（基类规则）。
##
## - 移动：在以出生点为中心的 ±roam_range 地盘里「找开火位置」，由**和玩家的水平距离**决定往哪走：
##   贴得太近（< close_range）就边退边打，离得太远（> far_range）就压进射程，不远不近就随机来回游走。
##   **永远不走出自己的地盘**，所以它不会像敌人 D 那样追着玩家跑（追击是 D 的定位，它靠射击）。
##   另外隔一段随机时间跳一下。
## - 射程 680（直线）：一出场，画面里任何位置的玩家都够得着（屏幕 640 宽）。
## - 射击：**导弹扇形**。背上的导弹巢一次打出 fan_count 发，以「导弹巢口 → 玩家身体中心」的方向为中心、
##   每发隔 fan_spread 度散开。导弹巢只朝前：扇形中心最多偏离水平 fan_max_angle 度，打不到正上方和身后。
##   瞄的是身体中心，趴下的玩家中心更低，扇形跟着往下压，所以**趴下躲不掉**，要站到两发之间的空隙里、或者跳开。
##   只在脚踏实地时开火（空中是喷射跳跃的动作），走动中照样打。
##   （素材只有朝前的导弹巢、没有能转的炮管，所以不做 8 方向单发；原来「玩家趴下就跳上高台打斜下」那套也跟着拿掉了——
##   扇形本来就打得到趴着的人。Boss 区域那块平台还在，只是普通地形。）
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

@export_group("Missile fan")
## 一轮打几发、相邻两发隔几度。
@export var fan_count := 5
@export var fan_spread := 20.0
## 扇形中心最多偏离水平几度（导弹巢朝前，不会朝正上、正下、身后打）。
@export var fan_max_angle := 60.0

@export_group("Grenade dodge")
## 落地的手雷离自己多近（水平）时开始躲。手雷爆炸半径 28 + 自己半个身宽，再留点余量。
@export var dodge_distance := 112.0
## 躲的时候水平移动多快。
@export var dodge_speed := 220.0

## 导弹巢口（相对身体中心，朝右时；朝左 x 取反）：机身顶上，贴图里导弹就是从这里冲出去的。
const POD_MUZZLE := Vector2(4, -22)

## 最近一轮扇形中心的方向（测试读）。
var fan_center := Vector2.LEFT
## 这一帧是否在躲手雷（测试读）。
var is_dodging := false

var _home := Vector2.ZERO
var _roam_dir := -1
var _turn_timer := 0.0
var _jump_timer := 0.0

func _ready() -> void:
	super()
	_home = global_position
	_turn_timer = randf_range(turn_time_min, turn_time_max)
	_jump_timer = randf_range(jump_interval_min, jump_interval_max)


func _boss_process(delta: float) -> void:
	_apply_gravity(delta)
	var threat := _grenade_threat()
	is_dodging = threat != null
	var target := find_target()
	# 优先级：躲手雷 > 平时走动。
	if is_dodging:
		_dodge(threat)
	else:
		_reposition(delta, target)
	move_and_slide()
	_report_motion()
	if is_on_wall():
		_roam_dir = -_roam_dir

	# 导弹巢朝前：有目标就转过去对着它，没有就朝走的方向
	var turn_to := signf(target.global_position.x - global_position.x) if target != null else signf(velocity.x)
	if turn_to != 0.0 and int(turn_to) != facing:
		facing = int(turn_to)
		_apply_visual_facing()
	_fire_timer -= delta
	if target != null and is_on_floor() and _fire_timer <= 0.0:
		_fire_timer = fire_interval
		fire_fan(target)


## 打一轮扇形：以导弹巢口指向目标身体中心的方向为中心（限制在朝前 ±fan_max_angle 以内），每发隔 fan_spread 度。
func fire_fan(target: Node2D) -> void:
	var point: Vector2 = target.body_center() if target is Player else target.global_position
	var offset := point - _muzzle_position()
	# 以「朝前水平」为 0 度量仰俯角，朝左时 x 翻过来算，最后再翻回去
	var pitch := clampf(atan2(offset.y, absf(offset.x)), -deg_to_rad(fan_max_angle), deg_to_rad(fan_max_angle))
	fan_center = Vector2(cos(pitch) * facing, sin(pitch))
	for i in fan_count:
		var angle := pitch + deg_to_rad(fan_spread) * (i - (fan_count - 1) / 2.0)
		_burst_direction = Vector2(cos(angle) * facing, sin(angle))
		_fire_one()


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


## 射程内（直线距离）看得见就打；扇形方向由 fire_fan 自己算。
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if global_position.distance_to(target.global_position) <= detect_range else -1


## 外观一直是朝前的导弹巢（没有能转的炮管）。
func shoot_direction() -> Vector2:
	return Vector2(facing, 0)


func _muzzle_position() -> Vector2:
	return global_position + Vector2(POD_MUZZLE.x * facing, POD_MUZZLE.y)
