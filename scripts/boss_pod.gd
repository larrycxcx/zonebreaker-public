class_name BossPod
extends Boss
## 第五关的**关底 Boss「生化舱」**（素材 `lab-tileset/boss/3`）。2026-11 和用户定的：会飞、横扫激光、三向炮、缩壳。
##
## 招式**按固定顺序轮着来**（`ROTATION`）：横扫激光 → 三向炮 → 缩壳 → 三向炮，打两轮就背得下来。
## 1. **横扫激光**：在空中停住蓄力（`charge_time`，预警），然后一边出光一边**往下压**（`sweep_speed`），
##    一直压到激光离地 `chest` 高（站着的人胸口）、停一下（`sweep_hold`）。激光打到墙为止（单向平台不挡）。
##    **躲法**：站在台子上的人跳下来，地上的人**趴下**——压到底的那一道从趴着的人头顶过去。
## 2. **三向炮**：飘到玩家斜上方，按玩家在哪挑炮——正下方用**正下炮**、斜下方用**斜下炮**、别处用**水平炮**
##    （素材自带三门：`Attack4_1/2/3`），每次一串（基类那套连发）。
## 3. **缩壳**：缩成一个圆壳（`shell_time`），**这段时间打不动**（子弹、手雷、终极武器都不扣血），
##    张开那一下朝四面八方打一圈子弹（`ring_count`），躲法是站进两发之间。
## **血过半**：节奏变快（`enrage_rush`），横扫压到底之后**再扫回去**（人刚站起来、刚跳回台子就挨），
## 一串炮多打两发，一圈子弹更密。只报一次 `boss_enrage`。
## 不出地盘（`roam_range`）；飞行高度按脚下的地面算（第一次行动时往下量一次）。

enum Move { HOVER, CHARGE, SWEEP, SWEEP_BACK, CANNON, SHELL }
enum Cannon { DOWN, DIAGONAL, LEVEL }

const ROTATION := [Move.CHARGE, Move.CANNON, Move.SHELL, Move.CANNON]

@export_group("Flight")
@export var roam_range := 220.0
## 平时飘在离地多高。
@export var hover_height := 150.0
@export var fly_speed := 90.0
## 打炮时飘到玩家旁边多远（斜下炮正好够得着）。
@export var side_offset := 110.0

@export_group("Sweep")
@export var charge_time := 0.8
@export var sweep_speed := 150.0
@export var sweep_hold := 0.3
@export var beam_damage := 56
@export var beam_range := 640.0
## 激光的半粗（素材那条 12 行粗）。
@export var beam_half := 6.0
## 压到底时激光离地多高：站着的人胸口（站着 32 高，趴下只有 12）。
@export var chest := 29.0

@export_group("Cannon")
@export var cannon_time := 2.2

@export_group("Shell")
@export var shell_time := 1.6
@export var ring_count := 8

@export_group("Rage")
@export_range(0.0, 1.0) var enrage_below := 0.5
@export var enrage_rush := 0.7
@export var rest_time := 0.8

## 激光从哪儿出（相对原点、朝右时）：眼睛前沿；素材里那条激光的中心比机身中心低 2。
const BEAM_ORIGIN := Vector2(19, 2)
## 三门炮的炮口（相对原点、朝右时），按贴图量的：不开火那一帧炮管的末端。
const CANNON_MUZZLES := {
	Cannon.DOWN: Vector2(3, 31),
	Cannon.DIAGONAL: Vector2(18, 29),
	Cannon.LEVEL: Vector2(20, 20),
}
const CANNON_CLIPS := {
	Cannon.DOWN: &"cannon_down",
	Cannon.DIAGONAL: &"cannon_diag",
	Cannon.LEVEL: &"cannon_level",
}

var move := Move.HOVER
var cannon := Cannon.LEVEL
var _left := 0.0
var _turn := 0
var _enraged := false
var _home := Vector2.ZERO
var _homed := false
var _floor_y := 0.0
var _burst_base := 3


func _boss_process(delta: float) -> void:
	if not _homed:
		_homed = true
		_home = global_position
		_burst_base = burst_max
		var space := get_world_2d().direct_space_state
		_floor_y = Sight.first_solid(space, global_position, global_position + Vector2(0, 2000)).y
	var target := _nearest()
	velocity = Vector2.ZERO
	match move:
		Move.HOVER:
			_left -= delta
			_face(target)
			_fly_to(_rest_spot(target), delta)
			if _left <= 0.0 and target != null:
				_start(ROTATION[_turn % ROTATION.size()])
				_turn += 1
		Move.CHARGE:
			_left -= delta
			if _left <= 0.0:
				_start(Move.SWEEP)
		Move.SWEEP:
			# 最后一步只走到底线为止，不冲过去
			velocity.y = minf(sweep_speed / _rush(), (sweep_floor() - beam_height()) / delta)
			_burn()
			if beam_height() >= sweep_floor() - 0.01:
				velocity.y = 0.0
				_left -= delta
				if _left <= 0.0:
					if _enraged:
						move = Move.SWEEP_BACK
					else:
						_rest()
		Move.SWEEP_BACK:
			# 二阶段：压到底再扫回去
			velocity.y = -sweep_speed / _rush()
			_burn()
			if global_position.y <= hover_y():
				_rest()
		Move.CANNON:
			_left -= delta
			_face(target)
			if target != null:
				_fly_to(Vector2(target.global_position.x - side_offset * facing, hover_y()), delta)
			try_shoot(delta, target)
			if _left <= 0.0:
				_rest()
		Move.SHELL:
			_left -= delta
			if _left <= 0.0:
				_pop_shell()
				_rest()
	move_and_slide()
	global_position.x = clampf(global_position.x, _home.x - roam_range, _home.x + roam_range)
	_show_beam()


func _start(next: Move) -> void:
	move = next
	match next:
		Move.CHARGE:
			_left = charge_time * _rush()
			_face(_nearest())
		Move.SWEEP:
			_left = sweep_hold
		Move.CANNON:
			_left = cannon_time
			_fire_timer = 0.2
		Move.SHELL:
			_left = shell_time * _rush()
			_set_shell(true)
	_show_beam()


func _rest() -> void:
	move = Move.HOVER
	_left = rest_time * _rush()
	_set_shell(false)
	_show_beam()


func _rush() -> float:
	return enrage_rush if _enraged else 1.0


## 缩着壳的时候什么都打不动（终极武器对 Boss 也是走这里扣血，所以一起挡住了）。
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	if is_shelled():
		return
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= max_health * enrage_below:
		_enraged = true
		burst_min = _burst_base + 2
		burst_max = _burst_base + 2
		GameEvents.report(&"boss_enrage", self)


# --- 激光 ---

## 平时飘的高度（原点的 y）。
func hover_y() -> float:
	return _floor_y - hover_height


## 横扫压到底时激光的高度。
func sweep_floor() -> float:
	return _floor_y - chest


func beam_height() -> float:
	return global_position.y + BEAM_ORIGIN.y


func beam_start() -> Vector2:
	return Vector2(global_position.x + BEAM_ORIGIN.x * facing, beam_height())


func beam_end() -> Vector2:
	var from := beam_start()
	return Sight.first_solid(get_world_2d().direct_space_state, from, from + Vector2(beam_range * facing, 0.0))


func _burn() -> void:
	var from := beam_start()
	var to := beam_end()
	var left := minf(from.x, to.x)
	var right := maxf(from.x, to.x)
	var y := beam_height()
	for player in players_by_distance():
		var box := player.hit_box()
		if box.end.x < left or box.position.x > right:
			continue
		if box.position.y > y + beam_half or box.end.y < y - beam_half:
			continue
		player.take_damage(roundi(beam_damage * Stage.damage_scale()), from, self)


func _show_beam() -> void:
	if _visual == null or not _visual.has_method(&"show_beam"):
		return
	var state := 0
	if move == Move.CHARGE:
		state = 1
	elif is_firing():
		state = 2
	var length := absf(beam_end().x - beam_start().x) if state == 2 else 0.0
	_visual.call(&"show_beam", state, length, BEAM_ORIGIN.y)


# --- 三向炮 ---

## 基类每一串开始时调一次：按玩家在哪挑炮。
func shoot_direction() -> Vector2:
	cannon = pick_cannon(_nearest())
	_play(CANNON_CLIPS[cannon])
	match cannon:
		Cannon.DOWN:
			return Vector2.DOWN
		Cannon.DIAGONAL:
			return Vector2(facing, 1).normalized()
	return Vector2(facing, 0)


func pick_cannon(target: Node2D) -> Cannon:
	if target == null:
		return Cannon.LEVEL
	var offset := target.global_position - global_position
	if offset.y <= 24.0:
		return Cannon.LEVEL
	if absf(offset.x) <= 32.0:
		return Cannon.DOWN
	var slope := offset.y / absf(offset.x)
	if slope >= 0.4 and slope <= 2.5:
		return Cannon.DIAGONAL
	return Cannon.DOWN if slope > 2.5 else Cannon.LEVEL


func _muzzle_position() -> Vector2:
	var at: Vector2 = CANNON_MUZZLES[cannon]
	return global_position + Vector2(at.x * facing, at.y)


# --- 缩壳 ---

func is_shelled() -> bool:
	return move == Move.SHELL


func _set_shell(on: bool) -> void:
	if _visual != null and _visual.has_method(&"show_shell"):
		_visual.call(&"show_shell", on)


## 张开那一下：朝四面八方打一圈（二阶段多一半）。
func _pop_shell() -> void:
	var count := ring_count + (ring_count / 2 if _enraged else 0)
	for i in count:
		var bullet := bullet_scene.instantiate() as Bullet
		bullet.direction = Vector2.RIGHT.rotated(TAU * i / count)
		if not is_equal_approx(Stage.damage_scale(), 1.0) and bullet.has_method("scale_damage"):
			bullet.scale_damage(Stage.damage_scale())
		get_parent().add_child(bullet)
		bullet.global_position = global_position
	GameEvents.report(shoot_event, self)


# --- 走位 ---

## 歇着的时候飘在哪：自己那一侧、离地 `hover_height`。
func _rest_spot(target: Node2D) -> Vector2:
	var x := _home.x
	if target != null:
		x = target.global_position.x - side_offset * 1.5 * signf(target.global_position.x - _home.x + 0.01)
	return Vector2(x, hover_y())


func _fly_to(spot: Vector2, delta: float) -> void:
	var gap := spot - global_position
	var speed := fly_speed / _rush()
	if gap.length() <= speed * delta:
		velocity = gap / delta
	else:
		velocity = gap.normalized() * speed


func _nearest() -> Player:
	var players := players_by_distance()
	return players[0] if not players.is_empty() else null


func _face(target: Node2D) -> void:
	if target == null:
		return
	var side := signi(target.global_position.x - global_position.x)
	if side != 0 and side != facing:
		facing = side
		_apply_visual_facing()


func _play(clip: StringName) -> void:
	if _visual != null and _visual.has_method(&"play"):
		_visual.call(&"play", clip)


func is_charging() -> bool:
	return move == Move.CHARGE


func is_firing() -> bool:
	return move == Move.SWEEP or move == Move.SWEEP_BACK


func is_enraged() -> bool:
	return _enraged


func floor_y() -> float:
	return _floor_y
