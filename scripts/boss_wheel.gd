class_name BossWheel
extends Boss
## Boss 3「独轮机甲」：一个踩在独轮上的大块头，在自己那片地盘里来回滚。
##
## **三招轮着来**（不是随机挑）——这样玩家打两轮就能背下节奏，死了也知道自己错在哪：
## 1. **炮击**：朝玩家打一串直线弹。中近距离的压制。
## 2. **抛弹**：把炸弹抛到空中砸下来（就是敌人的手雷，`Grenade` 本来就是抛物线、落地弹一下再炸）。
##    **它越得过掩体**——站在平台后面慢慢磨这一招专治。
## 3. **冲撞**：先前倾蓄一下，然后滚过去。**蓄力那一下就是留给玩家跳开的**。
##
## 和前两个 Boss 分得开：Boss A 铺扇形（站进空隙里躲）、Boss 2 飞在空中伸手臂抓（横向闪开），
## 这个是**地面重装**——三招分别管「远、掩体后、贴脸」，玩家得一直换位置。
##
## **血过半进第二阶段**：出手变快、滚得更快，并且报一声（`boss_enrage`，有声音和屏幕抖动）。

## 现在在干什么。
enum Move { ROAM, SHOOT, LOB, WINDUP, ROLL, REST }

@export_group("Movement")
## 地盘：以出生点为中心左右各多少像素。**不追出去**——走位是玩家的事。
@export var roam_range := 220.0
@export var roam_speed := 70.0
@export var turn_time_min := 1.0
@export var turn_time_max := 2.2

@export_group("Attacks")
## 两招之间歇多久。
@export var attack_rest := 1.1
## 炮击：射程以内才打。
@export var shoot_range := 520.0

@export_group("Lob")
## 抛弹用的发射物（敌人的手雷）。留空就不抛。
@export var bomb_scene: PackedScene
## 抛出点（相对身体中心，朝右时；朝左 x 取反）——举起来那条臂的位置。
@export var lob_offset := Vector2(6, -34)
## 举臂到脱手隔多久。素材里那道红色弹道就是这一下的预兆。
@export var lob_windup := 0.35
## 玩家在这个水平距离以内才值得抛（太近炸到自己、太远够不着）。
@export var lob_min := 80.0
@export var lob_max := 420.0

@export_group("Roll")
## 前倾蓄力多久。**这是留给玩家跳开的时间。**
@export var roll_windup := 0.5
@export var roll_speed := 260.0
@export var roll_time := 0.9

@export_group("Enraged")
## 血掉到这个比例以下进第二阶段。
@export_range(0.0, 1.0) var enrage_below := 0.5
## 第二阶段「出手更快」的倍率：歇的时间、蓄力的时间都乘它，滚的速度除以它。
@export var enrage_rush := 0.7

## 炮口（相对身体中心，朝右时）。
const CANNON := Vector2(36, -2)

var _move := Move.ROAM
var _left := 0.0
## 下一招轮到第几个（0 炮击 / 1 抛弹 / 2 冲撞）。
var _turn := 0
var _enraged := false

var _home := Vector2.ZERO
var _heading := 0
var _turn_left := 0.0


func _ready() -> void:
	super()
	_home = global_position
	_heading = -1
	_pick_heading()


func _boss_process(delta: float) -> void:
	_apply_gravity(delta)
	var target := find_target()
	match _move:
		Move.ROAM:
			_drift(delta)
			_left -= delta
			if _left <= 0.0 and target != null:
				_begin(target)
		Move.SHOOT:
			velocity.x = 0.0
			try_shoot(delta, target)
			if not is_firing_burst() and _fire_timer > 0.0:
				_rest()
		Move.LOB:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_release()
				_rest()
		Move.WINDUP:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_move = Move.ROLL
				_left = roll_time
				_report_motion(true)
		Move.ROLL:
			velocity.x = _speed(roll_speed) * facing
			_left -= delta
			if _left <= 0.0 or is_on_wall():
				_rest()
		Move.REST:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_move = Move.ROAM
				_left = 0.0
	move_and_slide()
	_report_motion(_move == Move.ROLL)


func move_kind() -> Move:
	return _move


func is_enraged() -> bool:
	return _enraged


## 掉到半血以下就换挡。**判断是「小于等于」而且每次挨打都查一次**：
## 一发手雷会从半血以上直接打到半血以下，写成「等于」的话绝大多数打法都跨过去了。
## **报一声**（声音 + 屏幕抖），不然玩家根本不知道它变了。只报一次。
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= float(max_health) * enrage_below:
		_enraged = true
		GameEvents.report(&"boss_enrage", self)


## 第二阶段歇得短、蓄得短。
func _timing(seconds: float) -> float:
	return seconds * enrage_rush if _enraged else seconds


## 第二阶段滚得快。
func _speed(value: float) -> float:
	return value / enrage_rush if _enraged else value


## 轮到下一招。够不着的那一招直接跳过去，不空等。
func _begin(target: Node2D) -> void:
	# **先把速度清零**：这一帧 `_drift()` 已经设过速度了，不清的话底下那次 `move_and_slide()`
	# 会带着漫游的速度走一帧——起手那一下看着像抽了一下。
	velocity.x = 0.0
	for i in 3:
		var pick: int = (_turn + i) % 3
		match pick:
			0:
				if absf(target.global_position.x - global_position.x) <= shoot_range:
					_face(target)
					_move = Move.SHOOT
					_fire_timer = 0.0
					_turn = pick + 1
					return
			1:
				var gap := absf(target.global_position.x - global_position.x)
				if bomb_scene != null and gap >= lob_min and gap <= lob_max:
					_face(target)
					_move = Move.LOB
					_left = _timing(lob_windup)
					_visual.aim(Vector2(facing, -1))
					_visual.fire()
					_turn = pick + 1
					return
			2:
				_face(target)
				_move = Move.WINDUP
				_left = _timing(roll_windup)
				_turn = pick + 1
				return
	_left = attack_rest


func _rest() -> void:
	_move = Move.REST
	_left = _timing(attack_rest)
	_visual.aim(Vector2(facing, 0))


func _face(target: Node2D) -> void:
	var side := signi(target.global_position.x - global_position.x)
	if side != 0 and side != facing:
		facing = side
		_apply_visual_facing()


## 抛一颗炸弹出去。**朝玩家那边抛**，`Grenade.launch()` 自己会加上抛，所以是条抛物线——
## 越得过掩体，正好治「躲在平台后面慢慢磨」。
func _release() -> void:
	if bomb_scene == null:
		return
	launch_projectile(bomb_scene, lob_offset, Vector2(facing, 0))
	GameEvents.report(&"grenade_throw", self)


## 在地盘里来回滚，到边就掉头。
func _drift(delta: float) -> void:
	_turn_left -= delta
	if _turn_left <= 0.0:
		_pick_heading()
	var offset := global_position.x - _home.x
	if absf(offset) > roam_range and signi(offset) == _heading:
		_heading = -_heading
	velocity.x = roam_speed * _heading
	if _heading != facing:
		facing = _heading
		_apply_visual_facing()


func _pick_heading() -> void:
	_turn_left = randf_range(turn_time_min, turn_time_max)
	_heading = -_heading


## 一串子弹全沿同一条线，朝玩家。
func shoot_direction() -> Vector2:
	var target := find_target()
	if target == null:
		return Vector2(facing, 0.0)
	return (target.call(&"body_center") - _muzzle_position()).normalized()


func _muzzle_position() -> Vector2:
	return body_center() + Vector2(CANNON.x * facing, CANNON.y)


## 够得着就打，方向由 `shoot_direction()` 现算。
func aim_for(target: Node2D) -> int:
	return Aim.LEVEL if within_reach(global_position.distance_to(target.global_position)) else -1
