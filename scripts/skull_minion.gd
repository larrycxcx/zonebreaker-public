class_name SkullMinion
extends Enemy
## 地下室 Boss 召唤出来的小骷髅：**满屏飞、绕着玩家转、隔一会儿扑过去**。
##
## 2026-10 试玩反馈后重做的：原来只是慢慢飘过来，被单向平台、实心块挡着，玩家躲在 Boss 底下根本够不着。
## 现在：
## - **穿墙**（场景里 `collision_mask` = 0）：地形挡不住它，但**不飞出画面**（每帧夹回摄像机看着的那块里）；
## - 平时**绕着玩家转圈**（`orbit_radius`），几只各转各的方向、相位错开，不会叠成一团；
## - 每隔 `dive_every` 秒**停一下、闪一下红**（`windup_time`，预兆），然后朝玩家那一刻的位置
##   **直线扑过去**（`dive_speed` 240，比玩家走路快），扑完接着转圈。
##   躲法是看见它闪红就横向挪开——它扑的是那一刻的位置，不拐弯。
## 碰到就扣血（接触伤害走玩家 Hurtbox 那一套），两枪打掉。

@export_group("Orbit")
@export var orbit_radius := 90.0
## 转圈的角速度（弧度 / 秒）和贴向那个圈的速度。
@export var orbit_speed := 1.6
@export var approach_speed := 90.0

@export_group("Dive")
@export var dive_speed := 240.0
@export var dive_time := 0.7
@export var windup_time := 0.4
## 两次扑之间隔多久（每只在这个范围里随机，免得一起扑）。
@export var dive_every_min := 1.6
@export var dive_every_max := 2.8
## 离画面边至少这么远（整个身子都在画面里）。
@export var screen_margin := 8.0

enum State {ORBIT, WINDUP, DIVE}

var state := State.ORBIT
var _left := 0.0
var _angle := 0.0
var _spin := 1.0
var _dive := Vector2.ZERO


func _ready() -> void:
	super()
	gravity = 0.0
	_angle = randf() * TAU
	_spin = 1.0 if randf() < 0.5 else -1.0
	_left = randf_range(dive_every_min, dive_every_max)


func _physics_process(delta: float) -> void:
	var target := find_target() as Player
	_left -= delta
	match state:
		State.ORBIT:
			if target == null:
				velocity = Vector2.ZERO
			else:
				_angle += orbit_speed * _spin * delta
				var spot := target.body_center() + Vector2.from_angle(_angle) * orbit_radius
				var to := spot - global_position
				velocity = to.limit_length(approach_speed * delta) / delta if to.length() > 0.5 else Vector2.ZERO
				if _left <= 0.0:
					state = State.WINDUP
					_left = windup_time
					velocity = Vector2.ZERO
					# 预兆：闪一下红（素材 Hurt2 那一帧整只骷髅是红的）
					_visual.flash_hit()
		State.WINDUP:
			velocity = Vector2.ZERO
			if _left <= 0.0:
				state = State.DIVE
				_left = dive_time
				var aim := (target.body_center() if target != null else global_position) - global_position
				_dive = aim.normalized() if aim.length() > 1.0 else Vector2(facing, 0)
		State.DIVE:
			velocity = _dive * dive_speed
			if _left <= 0.0:
				state = State.ORBIT
				_left = randf_range(dive_every_min, dive_every_max)
	if target != null:
		var side := signi(target.global_position.x - global_position.x)
		if side != 0 and side != facing:
			facing = side
			_apply_visual_facing()
	move_and_slide()
	_stay_on_screen()
	_report_motion(state == State.DIVE)


## 夹回画面里：它穿墙，不夹的话扑一下就飞出去、在画面外绕回来，玩家看不见它从哪儿来。
func _stay_on_screen() -> void:
	var rig := CameraRig.find(get_tree())
	if rig == null:
		return
	var view := rig.view_rect().grow(-screen_margin)
	global_position = global_position.clamp(view.position, view.end)


func is_diving() -> bool:
	return state == State.DIVE


func is_winding_up() -> bool:
	return state == State.WINDUP


## 看见就追：在画面里或者够得着就算，**不看视线**（它穿墙）。
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position))
