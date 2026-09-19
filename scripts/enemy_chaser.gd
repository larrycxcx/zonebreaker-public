class_name EnemyChaser
extends EnemyWalker
## 敌人 D：不开枪、不趴下，只靠碰撞伤人，血量和炮台一样。
## 平时用普通速度（move_speed）像巡逻兵一样来回走；直线距离 detect_range（150px）内看见玩家，
## 就用快 70% 的冲锋速度冲过去，能像玩家一样跳过墙、跳上平台。墙会挡住它的视线。
##
## 追丢（玩家翻到墙后、跑出视野）时会继续冲向最后看见玩家的位置，挡路就跳过去，
## memory_time 秒内还没重新看见就放弃，回去巡逻。这样「墙挡视线」和「会翻墙追人」才能同时成立：
## 一开始就躲在墙后它发现不了你，但被它盯上以后翻墙甩不掉它。

## 冲锋时的速度是巡逻速度的多少倍。
@export var charge_speed_scale := 1.7
## 跳跃力度和玩家一样，所以翻得过所有的墙（墙都比玩家跳跃高度低）。
@export var jump_velocity := -280.0
## 看丢玩家后，继续往最后看见的位置追多久。
@export var memory_time := 2.0
## 两次起跳之间至少隔多久，免得在够不着的平台下原地连跳。
@export var jump_cooldown := 0.5
## 玩家比自己高出这么多、而且水平距离在 climb_reach 以内时，起跳去够平台。
@export var climb_height := 20.0
@export var climb_reach := 24.0

var is_chasing := false

var _last_seen := Vector2.ZERO
var _memory_left := 0.0
var _jump_timer := 0.0


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_jump_timer -= delta

	var target := find_target()
	if target != null:
		_last_seen = target.global_position
		_memory_left = memory_time
	else:
		_memory_left -= delta
	is_chasing = _memory_left > 0.0

	if is_chasing:
		_chase(target != null)
	else:
		velocity.x = move_speed * facing
	move_and_slide()

	# 巡逻时和巡逻兵一样在悬崖、墙前掉头；追击时不掉头，悬崖直接跳下去，墙跳过去。
	if not is_chasing and _should_turn_around():
		facing = -facing
		_apply_facing()


## 直线距离以内、并且看得见的玩家。D 会跳，玩家在头顶平台上也要能发现，所以不用水平射程 + 高度差的判断。
func find_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	if global_position.distance_to(player.global_position) > detect_range:
		return null
	if not has_line_of_sight(player.body_center()):
		return null
	return player


func _chase(can_see: bool) -> void:
	var offset_x := _last_seen.x - global_position.x
	if absf(offset_x) > 2.0:
		var direction := signi(offset_x)
		if direction != facing:
			facing = direction
			_apply_facing()
		velocity.x = move_speed * charge_speed_scale * facing
	else:
		velocity.x = 0.0
		# 到了最后看见玩家的地方还是看不见，说明跟丢了。
		if not can_see:
			_memory_left = 0.0

	if not is_on_floor() or _jump_timer > 0.0:
		return
	var blocked := is_on_wall() or _wall_check.is_colliding()
	var target_above := global_position.y - _last_seen.y > climb_height and absf(offset_x) < climb_reach
	if blocked or target_above:
		velocity.y = jump_velocity
		_jump_timer = jump_cooldown
