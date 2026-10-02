class_name BossSkull
extends Boss
## 第四关（地下室）的 Boss「骷髅头」：飘在竖井顶上那一屏，**从侧面横扫激光**。
##
## 这一关是往上爬的，Boss 区是竖井最上面一屏、有几层平台。它的招都是逼玩家**换层**：
## 1. **激光**（主招）：在自己那一侧上下飘，对准玩家所在那一层；**停住蓄力**（攻击前两帧，
##    这段时间就是留给玩家看的预兆），然后一道激光横扫整个竖井，射到对面的墙为止
##    （单向平台不挡，和子弹一样）。躲法是**换一层**——跳上去、掉下去，或者蓄力时趴下：
##    激光对着站着的人的身体中心，6px 粗，趴下的人顶在它下面。
## 2. **召唤**：手里掉出小骷髅（`SkullMinion`），慢慢飞向玩家，碰到扣血、两枪打掉。
##    场上最多 `minion_cap` 个，不然堆满屏幕。
## 3. **换边**：每打两次从竖井这一侧飞到另一侧，激光有时从左边来、有时从右边来。
## 4. **骨弹**：玩家钻到它**正下方 / 正上方**（激光是从骨手往竖井中间射的，打不到它身边），
##    或者站在激光够不着的高度，它就朝玩家打一把扇形子弹（基类那套连发，每发偏开一点）。
##    **2026-10 试玩反馈**：原来只有激光，站在它底下就是安全区，Boss 很容易打。
##
## 轮换是固定的（激光、激光、召唤……），和独轮机甲一个道理：打两轮就背得下节奏，死了知道错在哪。
## **血过半进第二阶段**：先嘲讽一下（`sneer`）、报 `boss_enrage`（和前两个 Boss 同一个事件、同一条规矩：
## 小于等于半血、每次挨打都查、只报一次），之后蓄力变短，激光**连打两道**——先打玩家那一层，
## 紧接着打隔壁一层，只躲一下不够。
## 它死了，场上剩下的小骷髅一起碎掉（不给奖励——不是玩家打的）。

@export_group("Movement")
## 另一侧在出生点横向多远（出生在右侧就是负数）。竖井 576 宽，两侧各留 72。
@export var lane_offset := -448.0
## 从出生点往上最多飘多高（出生点就是最低的位置）。**够得着 Boss 区每一层就行**：
## 三层的人身体中心是 304 / 244 / 184，从 288 往上 120 就对得准最高那层。
## 不能再高：人站在地板上时画面是 60..420（摄像机往上多看 64），飘得太高它就出了画面、打冷枪。
@export var rise := 140.0
## 上下对齐的速度、换边飞过去的速度。
@export var climb_speed := 140.0
@export var cross_speed := 260.0
## 对齐最多等多久（玩家一直在跳，追不上也要开打）。
@export var align_time := 1.2

@export_group("Beam")
@export var charge_time := 0.7
@export var beam_time := 0.45
@export var beam_damage := 60
## 激光有多粗的一半（判定）。和画面那条 6px 粗的对得上。
@export var beam_half := 3.0
## 激光最远射多远（射到墙为止，这只是上限）。
@export var beam_range := 640.0
## 两次攻击之间歇多久。
@export var rest_time := 0.8

@export_group("Volley")
## 玩家离它横向这么近（在它正下方 / 正上方）就改打骨弹——激光打不到身边。
@export var under_reach := 120.0
## 扇形里每发偏开多少度。一轮几发、间隔多久用基类的 `burst_min/max`、`burst_gap`（场景里配）。
@export var volley_spread := 15.0

@export_group("Summon")
@export var minion_scene: PackedScene
## 每几次攻击召唤一次（第几次轮到召唤）。
@export var summon_every := 3
@export var summon_count := 2
@export var minion_cap := 3

@export_group("Enraged")
@export_range(0.0, 1.0) var enrage_below := 0.5
## 第二阶段蓄力乘这个（变短）。
@export var enrage_rush := 0.6
## 第二道激光打隔壁一层：上下差多少（就是一层的高度）。
@export var second_beam_step := 60.0
@export var sneer_time := 0.5

## 激光从骨手哪儿射出来（相对身体中心，朝右时；朝左 x 取反）。按贴图量的：手在 (52, 64~67)，身子中心 (32, 50)。
const BEAM_ORIGIN := Vector2(20, 16)
## 召唤时小骷髅在第几帧掉出来（Attack3 第 5 帧，一次性动作 12 帧 / 秒）。
const SUMMON_DROP := 4.0 / EnemySpriteAppearance.ONCE_FPS
const SUMMON_TIME := 6.0 / EnemySpriteAppearance.ONCE_FPS

enum Move {ALIGN, CHARGE, BEAM, REST, SUMMON, SWAP, SNEER, VOLLEY}

var _move := Move.REST
var _left := 0.0
var _home := Vector2.ZERO
var _lanes: Array[float] = []
var _lane := 0
## 激光锁定在哪个高度（世界坐标的 y），以及这一轮已经打了几道。
var _beam_y := 0.0
var _beams_this_round := 0
var _attacks := 0
var _summoned := false
var _enraged := false
var _minions: Array[Enemy] = []
## 骨弹这一轮开打了没有、这一轮打到第几发（铺扇形用）。
var _volley_started := false
var _fan_index := 0


func _ready() -> void:
	super()
	_home = global_position
	_lanes = [_home.x, _home.x + lane_offset]
	_left = rest_time


func _boss_process(delta: float) -> void:
	_forget_dead_minions()
	var target := find_target()
	_face_the_shaft()
	match _move:
		Move.ALIGN:
			_left -= delta
			var goal := _goal_height(target)
			velocity = Vector2(0.0, clampf((goal - global_position.y) / delta, -climb_speed, climb_speed))
			if target != null and wants_volley(target) and _beams_this_round == 0:
				# 对齐到一半人钻到它底下了：激光打不到，改打骨弹
				velocity = Vector2.ZERO
				_start_volley()
			elif target != null and absf(goal - global_position.y) < 1.0:
				# **对齐了就直接放到那个高度上**：差的那不到一像素是歇着时上下浮动带来的零头，
				# 不抹掉的话锁定的激光高度每次都不一样
				global_position.y = goal
				_start_charge()
			elif target != null and _left <= 0.0:
				_start_charge()
		Move.CHARGE:
			velocity = Vector2.ZERO
			_left -= delta
			if _left <= 0.0:
				_move = Move.BEAM
				_left = beam_time
		Move.BEAM:
			velocity = Vector2.ZERO
			_burn()
			_left -= delta
			if _left <= 0.0:
				_beams_this_round += 1
				if _enraged and _beams_this_round < 2:
					_beam_y = _second_beam_height(target)
					_move = Move.ALIGN
					_left = align_time
				else:
					_finish_attack()
		Move.REST:
			velocity = _hover(delta)
			_left -= delta
			if _left <= 0.0 and target != null:
				_next_attack()
		Move.SUMMON:
			velocity = Vector2.ZERO
			_left -= delta
			if not _summoned and SUMMON_TIME - _left >= SUMMON_DROP:
				_summon()
			if _left <= 0.0:
				_finish_attack()
		Move.SWAP:
			var to := Vector2(_lanes[_lane], global_position.y)
			var step := to - global_position
			velocity = step.limit_length(cross_speed * delta) / delta
			if step.length() < 1.0:
				_move = Move.ALIGN
				_left = align_time
		Move.VOLLEY:
			velocity = Vector2.ZERO
			try_shoot(delta, target if not _volley_started else null)
			if not _volley_started and is_firing_burst():
				_volley_started = true
			elif _volley_started and not is_firing_burst():
				_finish_attack()
		Move.SNEER:
			velocity = Vector2.ZERO
			_left -= delta
			if _left <= 0.0:
				_move = Move.REST
				_left = rest_time * 0.5
	move_and_slide()
	# 移动完再对一次朝向：换边刚飞到的那一帧，前面那次还是朝着目的地的
	_face_the_shaft()
	_report_motion(_move == Move.SWAP)
	_show_beam()


## 这一下要飘到多高：激光出口（身体中心下面 16）对准玩家的身体中心。
## 第二道激光已经锁好了高度（`_beam_y`），就照那个飘。
func _goal_height(target: Node2D) -> float:
	var want := global_position.y
	if _enraged and _beams_this_round == 1:
		want = _beam_y - BEAM_ORIGIN.y
	elif target != null:
		want = (target as Player).body_center().y - BEAM_ORIGIN.y
	return clampf(want, _home.y - rise, _home.y)


func _start_charge() -> void:
	_beam_y = global_position.y + BEAM_ORIGIN.y
	_move = Move.CHARGE
	_left = charge_time * (enrage_rush if _enraged else 1.0)
	# 第二道激光的蓄力更短：它是紧接着第一道来的
	if _enraged and _beams_this_round == 1:
		_left *= 0.5


## 第二道打隔壁一层：玩家已经换了层就追着他打，没换就打他上面（或下面，上面没地方了的话）那一层。
func _second_beam_height(target: Node2D) -> float:
	var first := _beam_y
	if target != null:
		var now := (target as Player).body_center().y
		if absf(now - first) > beam_half * 4.0:
			return now
	var up := first - second_beam_step
	var lowest_origin := _home.y - rise + BEAM_ORIGIN.y
	return up if up >= lowest_origin else first + second_beam_step


func _next_attack() -> void:
	_attacks += 1
	_beams_this_round = 0
	var target := find_target()
	if _attacks % summon_every == 0 and _minions.size() < minion_cap:
		_move = Move.SUMMON
		_left = SUMMON_TIME
		_summoned = false
		if _visual.has_method(&"play"):
			_visual.call(&"play", &"summon")
	elif target != null and wants_volley(target):
		_start_volley()
	elif _attacks % 2 == 0:
		_lane = 1 - _lane
		_move = Move.SWAP
	else:
		_move = Move.ALIGN
		_left = align_time


## 激光打不到这个人吗：在它身边（正下方 / 正上方，激光是往竖井中间射的），
## 或者在它飘得到的高度以外（激光只能横着打）。
func wants_volley(target: Node2D) -> bool:
	var player := target as Player
	var at := player.body_center() if player != null else target.global_position
	if absf(at.x - global_position.x) < under_reach:
		return true
	var lowest := _home.y + BEAM_ORIGIN.y
	var highest := _home.y - rise + BEAM_ORIGIN.y
	return at.y > lowest + 24.0 or at.y < highest - 24.0


func _start_volley() -> void:
	_move = Move.VOLLEY
	_volley_started = false
	_fire_timer = 0.0


func is_volleying() -> bool:
	return _move == Move.VOLLEY


## 骨弹这一轮朝哪儿：从骨手对着玩家的身体中心（往下往上都行）。基类在一轮开始时调一次，顺手把扇形计数归零。
func shoot_direction() -> Vector2:
	_fan_index = 0
	var target := find_target()
	if target == null:
		return Vector2(facing, 0.0)
	return ((target as Player).body_center() - _muzzle_position()).normalized()


## 这一发：在锁定的方向上左右铺开（中间那发正对着人）。
func burst_direction() -> Vector2:
	var count := maxi(1, burst_max)
	var step := (_fan_index % count) - (count - 1) / 2.0
	_fan_index += 1
	return super().rotated(deg_to_rad(step * volley_spread))


## 骨弹从骨手出去（和激光同一个口）。
func _muzzle_position() -> Vector2:
	return global_position + Vector2(BEAM_ORIGIN.x * facing, BEAM_ORIGIN.y)


func _finish_attack() -> void:
	_move = Move.REST
	_left = rest_time


## 把已经死了的小骷髅从名单里去掉。
## **不能用 `filter(func(m: Enemy) ...)`**：玩家的子弹在 Boss 之后处理，小骷髅被打死的那一帧末尾就释放了，
## 下一帧这里拿到的是一个已经释放的对象——传给带类型的参数会报错，`filter` 再返回一个不带类型的数组，
## 赋回 `Array[Enemy]` 又报一次，每帧都报（2026-10 试玩时编辑器就停在这儿，看着像崩了）。
## 循环变量也不标类型，先问 `is_instance_valid` 再用。
func _forget_dead_minions() -> void:
	var alive: Array[Enemy] = []
	for minion in _minions:
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			alive.append(minion)
	_minions = alive


## 小骷髅从骨手下面掉出来，场上不超过上限。
func _summon() -> void:
	_summoned = true
	if minion_scene == null:
		return
	for i in summon_count:
		if _minions.size() >= minion_cap:
			break
		var minion := minion_scene.instantiate() as Enemy
		get_parent().add_child(minion)
		minion.global_position = global_position + Vector2(BEAM_ORIGIN.x * facing, BEAM_ORIGIN.y + 8.0 * i)
		_minions.append(minion)


## 出光那几帧：凡是身子碰到那条横带的都挨一下（无敌帧会挡住同一道的第二下）。
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


## 激光从哪儿出、射到哪儿（射到第一个实心物体为止，单向平台不挡）。
func beam_start() -> Vector2:
	return Vector2(global_position.x + BEAM_ORIGIN.x * facing, _beam_y)


func beam_end() -> Vector2:
	var from := beam_start()
	return Sight.first_solid(get_world_2d().direct_space_state, from, from + Vector2(beam_range * facing, 0.0))


## 激光的高度（世界坐标，测试用）。
func beam_height() -> float:
	return _beam_y


func is_charging() -> bool:
	return _move == Move.CHARGE


func is_firing() -> bool:
	return _move == Move.BEAM


func is_swapping() -> bool:
	return _move == Move.SWAP


func is_enraged() -> bool:
	return _enraged


func minions() -> Array[Enemy]:
	return _minions


func _show_beam() -> void:
	if not _visual.has_method(&"show_beam"):
		return
	var state := 0
	if _move == Move.CHARGE or _move == Move.VOLLEY:
		# 骨弹没有专门的姿势，用蓄力那两帧（骨手在发光）
		state = 1
	elif _move == Move.BEAM:
		state = 2
	var length := absf(beam_end().x - beam_start().x) if state == 2 else 0.0
	_visual.call(&"show_beam", state, length, _beam_y - global_position.y)


## 永远朝着竖井中间（另一侧那条道）：激光要横扫整个竖井。
func _face_the_shaft() -> void:
	var side := signi(_lanes[1 - _lane] - global_position.x) if _move != Move.SWAP \
		else signi(_lanes[_lane] - global_position.x)
	if side != 0 and side != facing:
		facing = side
		_apply_visual_facing()


## 歇着的时候轻轻上下浮动（漂着的东西不能是死的）。
func _hover(_delta: float) -> Vector2:
	return Vector2(0.0, 6.0 * sin(Time.get_ticks_msec() / 400.0))


## 它不分水平 / 斜射：在画面里（或者够得着）就有反应，不看视线——它是飘在竖井里的。
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position))


## 血过半换挡：嘲讽一下、报一声，之后蓄力变短、激光打两道。
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= float(max_health) * enrage_below:
		_enraged = true
		_move = Move.SNEER
		_left = sneer_time
		if _visual.has_method(&"play"):
			_visual.call(&"play", &"sneer")
		GameEvents.report(&"boss_enrage", self)


## 它死了，小骷髅一起碎掉——**不给奖励**，那不是玩家打下来的。
func die() -> void:
	for minion in _minions:
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			minion.xp_reward = 0
			minion.money_reward = 0
			minion.die()
	_minions.clear()
	super()
