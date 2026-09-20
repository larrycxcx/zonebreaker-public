class_name EnemyFlyer
extends Enemy
## 敌人 E：会飞，不受重力。在固定高度附近以波浪轨迹来回巡逻，水平速度和普通敌人一样。
## 玩家出现在它**垂直下方**（水平距离 below_width 以内，且看得见）时开始跟随：在上空朝玩家水平移动，
## 玩家在正下方时竖直向下开火。子弹和其它子弹一样穿过单向平台，被地面、墙、矮通道这些实心物体挡住。
## 跟随中看不见玩家或玩家水平离开 follow_range 以外，memory_time 秒后放弃，就地继续巡逻。

@export var move_speed := 60.0
## 跟随玩家时的水平速度。
@export var follow_speed := 60.0
@export_enum("左:-1", "右:1") var start_direction := -1
## 巡逻范围：巡逻中心左右各多少像素。
@export var patrol_distance := 180.0
## 波浪的振幅（像素）和周期（秒）。
@export var wave_amplitude := 16.0
@export var wave_period := 2.0
## 玩家和它的水平距离在这个范围内，就算在它「垂直下方」。
@export var below_width := 20.0
## 跟随时玩家水平离开多远就算跟丢。
@export var follow_range := 280.0
@export var memory_time := 1.5

var is_following := false

## 波浪围绕的高度和巡逻中心。出生时取当前位置，用 set_anchor() 可以改。
var _base_y := 0.0
var _patrol_center_x := 0.0
var _wave_time := 0.0
var _memory_left := 0.0


func _ready() -> void:
	super()
	facing = start_direction
	_apply_visual_facing()
	set_anchor(global_position)


## 把它放到 position，并以这里为波浪高度和巡逻中心。
func set_anchor(position_: Vector2) -> void:
	global_position = position_
	_base_y = position_.y
	_patrol_center_x = position_.x
	_wave_time = 0.0


func _physics_process(delta: float) -> void:
	_wave_time += delta
	var target := find_target()
	var below := target != null and absf(target.global_position.x - global_position.x) <= below_width

	if below:
		is_following = true
	if is_following:
		if target != null:
			_memory_left = memory_time
			_follow(delta, target)
		else:
			velocity.x = 0.0
			_memory_left -= delta
			if _memory_left <= 0.0:
				# 跟丢了：以现在的位置为中心继续巡逻，而不是飞回出生点。
				is_following = false
				_patrol_center_x = global_position.x
	else:
		velocity.x = move_speed * facing

	# 波浪：每帧把高度拉到正弦曲线上的目标值。
	var wave_y := _base_y + wave_amplitude * sin(TAU * _wave_time / wave_period)
	velocity.y = (wave_y - global_position.y) / delta
	move_and_slide()

	if not is_following and _should_turn_around():
		_set_facing(-facing)

	try_shoot(delta, target if below else null)


## 能跟随的玩家：在它下方、水平 follow_range 以内、看得见（视线从枪口往下）。
func find_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	var offset := player.global_position - global_position
	if offset.y <= 0.0 or absf(offset.x) > follow_range:
		return null
	if not has_line_of_sight(player.body_center()):
		return null
	return player


func shoot_direction() -> Vector2:
	return Vector2.DOWN


func _follow(delta: float, target: Node2D) -> void:
	var offset_x := target.global_position.x - global_position.x
	if absf(offset_x) > follow_speed * delta:
		_set_facing(signi(offset_x))
		velocity.x = follow_speed * facing
	else:
		velocity.x = 0.0


## 巡逻到范围边缘、或者撞到墙就掉头。
func _should_turn_around() -> bool:
	var past_edge := (global_position.x - _patrol_center_x) * facing >= patrol_distance
	return past_edge or is_on_wall()


func _set_facing(value: int) -> void:
	if value == facing:
		return
	facing = value
	_apply_visual_facing()
