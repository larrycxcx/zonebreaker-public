class_name BossGunner
extends Boss
## 第五关的**中段小 Boss**「变异枪手」（素材 `lab-tileset/boss/1`）。2026-11 和用户定的：
## 关卡中间一间闸门封住的房间里，**打死它不算通关**（`ends_level` 关着），打死了前面的门才开。
##
## 招式**按固定顺序轮着来**（`ROTATION`）：蓄力激光 → 边走边打的激光弹 → 枪托冲撞；
## 玩家贴到 `kick_range` 以内时插一记**前踢**（把人踹开）。
## 1. **蓄力激光**：站住、播蓄力那几帧（`charge_time`，预警），然后一道横着的激光**打到墙为止**（`Sight.first_solid`，
##    单向平台不挡），高度在胸口——**趴下躲得掉**（和「站着开的枪从趴着的人头顶飞过」是同一条规矩）。
## 2. **激光弹**：朝玩家走、一边打一串（基类那套连发，`bullet_scene`）。
## 3. **枪托冲撞**：蹲一下蓄力（`lunge_windup`），然后猛地往前冲一段（`lunge_speed` × `lunge_time`），撞上就挨一下。
## **血过半**：节奏变快（`enrage_rush`），蓄力激光变成**两道**——先胸口一道（趴下躲），紧接着**原地蹦起来**
## （`hop_height`），在最高点停住再水平打一道：那一道离地约 50，站在地上的人头顶擦过、跳起来反而挨，
## 不能一直趴着。素材里没有举高枪的姿势，所以高的那道靠「人蹦起来」打，激光照样从枪口出去；蹦那一下也是预兆。
## 只报一次 `boss_enrage`。
## 不追出地盘（`roam_range`，以出生点为中心），那间房就是它的地盘。

enum Move { IDLE, CHARGE, BEAM, BOLTS, LUNGE_WINDUP, LUNGE, KICK, HOP }

const ROTATION := [Move.CHARGE, Move.BOLTS, Move.LUNGE_WINDUP]

@export_group("Arena")
@export var roam_range := 200.0
@export var walk_speed := 70.0
@export var keep_distance := 180.0

@export_group("Laser")
@export var charge_time := 0.7
@export var beam_time := 0.45
@export var beam_damage := 52
@export var beam_range := 640.0
## 激光的半粗（判定是一条横带）。
@export var beam_half := 3.0
## 第一道激光比原点低多少（负数 = 高）：素材里激光在第 41~45 行，原点在第 48 行 → 高 5，离地约 29（胸口）。
@export var beam_low := -5.0
## 二阶段第二道之前蹦多高：在最高点打，激光离地约 29 + 21 = 50（站着的人头顶上面一点，跳起来正好挨）。
@export var hop_height := 21.0

@export_group("Bolts")
@export var bolt_time := 1.6

@export_group("Lunge")
@export var lunge_windup := 0.45
@export var lunge_speed := 320.0
@export var lunge_time := 0.35
@export var lunge_damage := 48

@export_group("Kick")
@export var kick_range := 44.0
@export var kick_time := 0.5
@export var kick_hit_at := 0.25
@export var kick_damage := 40
@export var kick_push := Vector2(520, -200)

@export_group("Rage")
@export_range(0.0, 1.0) var enrage_below := 0.5
@export var enrage_rush := 0.7
@export var rest_time := 0.8

## 激光从哪儿出（相对原点、朝右时）：枪口那一截。
const BEAM_ORIGIN := Vector2(36, 0)

var move := Move.IDLE
var _left := 0.0
var _turn := 0
var _beams_left := 0
var _beam_y := 0.0
var _kicked := false
var _enraged := false
var _home := Vector2.ZERO
var _lunge_hit := false
## 蹦到最高点打第二道的时候悬在空中（不受重力），打完才落下来。
var _hovering := false


var _homed := false


func _boss_process(delta: float) -> void:
	# 地盘的中心在第一次行动时才记（出场时站在哪儿就是哪儿；生成后再摆位的也对）
	if not _homed:
		_homed = true
		_home = global_position
	_apply_gravity(delta)
	var target := _nearest()
	match move:
		Move.IDLE:
			_left -= delta
			_face(target)
			velocity.x = 0.0
			if target != null and _close(target, kick_range):
				_start(Move.KICK)
			elif _left <= 0.0 and target != null:
				_start(ROTATION[_turn % ROTATION.size()])
				_turn += 1
		Move.CHARGE:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_start(Move.BEAM)
		Move.BEAM:
			velocity.x = 0.0
			if _hovering:
				velocity.y = 0.0
			_left -= delta
			_burn()
			if _left <= 0.0:
				_beams_left -= 1
				_hovering = false
				if _beams_left > 0:
					# 二阶段的第二道：先蹦起来，到最高点再打
					move = Move.HOP
					velocity.y = -sqrt(2.0 * gravity * hop_height)
					_show_beam()
				else:
					_rest()
		Move.HOP:
			velocity.x = 0.0
			if velocity.y >= 0.0:
				move = Move.BEAM
				_left = beam_time
				_hovering = true
				velocity.y = 0.0
				_beam_y = global_position.y + beam_low
		Move.BOLTS:
			_left -= delta
			_face(target)
			var gap := absf(target.global_position.x - global_position.x) if target != null else 0.0
			velocity.x = walk_speed * facing if gap > keep_distance else 0.0
			try_shoot(delta, update_aim(delta, target))
			if _left <= 0.0:
				_rest()
		Move.LUNGE_WINDUP:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_start(Move.LUNGE)
		Move.LUNGE:
			_left -= delta
			velocity.x = lunge_speed * facing
			_lunge_contact()
			if _left <= 0.0:
				_rest()
		Move.KICK:
			velocity.x = 0.0
			_left -= delta
			if not _kicked and kick_time - _left >= kick_hit_at:
				_kicked = true
				_land_kick()
			if _left <= 0.0:
				_rest()
	_stay_home()
	move_and_slide()
	# 冲撞一帧走 5 像素，停在线外一点也要夹回来
	global_position.x = clampf(global_position.x, _home.x - roam_range, _home.x + roam_range)


func _start(next: Move) -> void:
	move = next
	var rush := enrage_rush if _enraged else 1.0
	match next:
		Move.CHARGE:
			_left = charge_time * rush
			_play(&"charge")
		Move.BEAM:
			_left = beam_time
			_beams_left = 2 if _enraged else 1
			_beam_y = global_position.y + beam_low
			_play(&"beam")
		Move.BOLTS:
			_left = bolt_time
		Move.LUNGE_WINDUP:
			_left = lunge_windup * rush
			_play(&"lunge")
		Move.LUNGE:
			_left = lunge_time
			_lunge_hit = false
		Move.KICK:
			_left = kick_time
			_kicked = false
			_play(&"kick")
	_show_beam()


func _rest() -> void:
	move = Move.IDLE
	_left = rest_time * (enrage_rush if _enraged else 1.0)
	_show_beam()


func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= max_health * enrage_below:
		_enraged = true
		GameEvents.report(&"boss_enrage", self)


## 出光那几帧：身子碰到那条横带的都挨一下（无敌帧挡住同一道的第二下）。
func _burn() -> void:
	var from := beam_start()
	var to := beam_end()
	var left := minf(from.x, to.x)
	var right := maxf(from.x, to.x)
	for player in players_by_distance():
		var box := player.hit_box()
		if box.end.x < left or box.position.x > right:
			continue
		if box.position.y > _beam_y + beam_half or box.end.y < _beam_y - beam_half:
			continue
		player.take_damage(roundi(beam_damage * Stage.damage_scale()), from, self)
	_show_beam()


func beam_start() -> Vector2:
	return Vector2(global_position.x + BEAM_ORIGIN.x * facing, _beam_y)


func beam_end() -> Vector2:
	var from := beam_start()
	return Sight.first_solid(get_world_2d().direct_space_state, from, from + Vector2(beam_range * facing, 0.0))


func _lunge_contact() -> void:
	if _lunge_hit:
		return
	var reach := Rect2(global_position + Vector2(-16.0 + 12.0 * facing, -24.0), Vector2(32, 48))
	for player in players_by_distance():
		if reach.intersects(player.hit_box()):
			_lunge_hit = true
			player.take_damage(roundi(lunge_damage * Stage.damage_scale()), global_position, self)


func _land_kick() -> void:
	for player in players_by_distance():
		if _close(player, kick_range + 8.0):
			var landed := not player.is_invincible()
			player.take_damage(roundi(kick_damage * Stage.damage_scale()), global_position, self)
			if landed:
				player.shove(Vector2(kick_push.x * facing, kick_push.y))


## 不出自己那块地盘：走到边上就停（冲撞冲到边上也停）。
func _stay_home() -> void:
	var low := _home.x - roam_range
	var high := _home.x + roam_range
	if (global_position.x <= low and velocity.x < 0.0) or (global_position.x >= high and velocity.x > 0.0):
		velocity.x = 0.0


func _nearest() -> Player:
	var players := players_by_distance()
	return players[0] if not players.is_empty() else null


func _close(player: Player, distance: float) -> bool:
	return absf(player.global_position.x - global_position.x) <= distance \
		and absf(player.global_position.y - global_position.y) <= 40.0


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


func _show_beam() -> void:
	if _visual == null or not _visual.has_method(&"show_beam"):
		return
	var state := 0
	if move == Move.CHARGE or move == Move.HOP:
		state = 1
	elif move == Move.BEAM:
		state = 2
	var length := absf(beam_end().x - beam_start().x) if state == 2 else 0.0
	_visual.call(&"show_beam", state, length, _beam_y - global_position.y)


func is_charging() -> bool:
	return move == Move.CHARGE


func is_firing() -> bool:
	return move == Move.BEAM


func is_enraged() -> bool:
	return _enraged


func beam_height() -> float:
	return _beam_y
