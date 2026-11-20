class_name EnemyBurrower
extends EnemyChaser
## 第五关的 5-E：**埋在地下的蜘蛛爪臂**（爪臂头 + 蜘蛛腿）。2026-11 和用户定的：
## - **埋着**：地上只露一块履带（素材包的外观；占位方块画成半透明），那就是提醒。埋着的时候碰撞层清空——
##   打不到、撞不到，终极武器也炸不着它。
## - 玩家走近（左右 `trigger_range` 以内、和它差不多同一层）→ **钻出来**：履带滑开、机甲升上来（`emerge_time`），
##   钻完才恢复碰撞。
## - 钻出来之后就是 D 那套**追击**（蜘蛛腿走得动、能跳上平台、翻墙）。
## - 贴到 `spin_range` 以内 → 站住**原地旋转**（`spin_time`）：一边播爪臂横扫那几帧、一边快速左右翻身，
##   转到一半那一下**左右两边都打**（`spin_radius` 以内的人挨一下）。转完**歇一会儿**（`rest_time`）——反击的时机。

enum State { BURIED, EMERGING, HUNTING, SPINNING, RESTING }

@export_group("Burrow")
@export var trigger_range := 110.0
## 和它的高度差在这以内才算「同一层」（不然楼上走过去它就钻出来了）。
@export var trigger_height := 48.0
@export var emerge_time := 0.7
@export var emerge_event := &"chaser_alert"

@export_group("Spin")
@export var spin_range := 40.0
@export var spin_time := 0.8
## 转到多久的时候打（这时候爪臂正扫过身边）。
@export var spin_hit_at := 0.4
@export var spin_radius := 46.0
@export var spin_damage := 48
## 每隔多久翻一次身（快速左右翻 = 转圈）。
@export var spin_flip := 0.1
@export var rest_time := 0.7

var state := State.BURIED
var _left := 0.0
var _flip_left := 0.0
var _spun := false
var _layer := 8


func _ready() -> void:
	super()
	_layer = collision_layer
	bury()


## 埋回去（关卡一开始就是这个样子）。
func bury() -> void:
	state = State.BURIED
	collision_layer = 0
	velocity = Vector2.ZERO
	if _visual != null and _visual.has_method(&"show_buried"):
		_visual.call(&"show_buried", true)


func is_buried() -> bool:
	return state == State.BURIED or state == State.EMERGING


func _physics_process(delta: float) -> void:
	match state:
		State.BURIED:
			if _someone_near():
				_start_emerging()
		State.EMERGING:
			_left -= delta
			if _left <= 0.0:
				state = State.HUNTING
				collision_layer = _layer
		State.HUNTING:
			super(delta)
			var target := _spin_target()
			if target != null and is_on_floor():
				_start_spin()
		State.SPINNING:
			_spin(delta)
		State.RESTING:
			_left -= delta
			velocity.x = 0.0
			_apply_gravity(delta)
			move_and_slide()
			if _left <= 0.0:
				state = State.HUNTING


## 埋着的时候终极武器炸不着（它在地底下）。
func hit_by_ultimate(from: Node = null) -> void:
	if is_buried():
		return
	super(from)


func _someone_near() -> bool:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) <= trigger_range and absf(offset.y) <= trigger_height:
			return true
	return false


func _start_emerging() -> void:
	state = State.EMERGING
	_left = emerge_time
	# 钻出来就冲着最近的那个人
	var players := players_by_distance()
	if not players.is_empty():
		facing = signi(players[0].global_position.x - global_position.x)
		if facing == 0:
			facing = 1
		_apply_facing()
	if _visual != null and _visual.has_method(&"emerge"):
		_visual.call(&"emerge")
	GameEvents.report(emerge_event, self)


func _spin_target() -> Player:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if absf(offset.x) <= spin_range and absf(offset.y) <= trigger_height:
			return player
	return null


func _start_spin() -> void:
	state = State.SPINNING
	_left = spin_time
	_flip_left = spin_flip
	_spun = false
	velocity.x = 0.0
	if _visual != null:
		_visual.fire()


func _spin(delta: float) -> void:
	_left -= delta
	_flip_left -= delta
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if _flip_left <= 0.0:
		_flip_left = spin_flip
		facing = -facing
		_apply_facing()
	if not _spun and spin_time - _left >= spin_hit_at:
		_spun = true
		_land_spin()
	if _left <= 0.0:
		state = State.RESTING
		_left = rest_time


## 转到一半：身边（左右两边都算）的人挨一下。
func _land_spin() -> void:
	for player in players_by_distance():
		if player.body_center().distance_to(body_center()) <= spin_radius:
			player.take_damage(roundi(spin_damage * Stage.damage_scale()), body_center(), self)


func is_spinning() -> bool:
	return state == State.SPINNING


func is_resting() -> bool:
	return state == State.RESTING
