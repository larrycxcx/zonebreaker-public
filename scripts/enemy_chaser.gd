class_name EnemyChaser
extends EnemyWalker
## 敌人 D：不开枪、不趴下，只靠碰撞伤人，血量和炮台一样。
## 平时用普通速度（move_speed）像巡逻兵一样来回走；直线距离 detect_range（150px）内看见玩家，
## 就用冲锋速度（和玩家奔跑一样快）冲过去，能像玩家一样跳过墙、跳上平台。墙会挡住它的视线。
##
## 追丢（玩家翻到墙后、跑出视野）时会继续冲向最后看见玩家的位置，挡路就跳过去，
## memory_time 秒内还没重新看见就放弃，回去巡逻。这样「墙挡视线」和「会翻墙追人」才能同时成立：
## 一开始就躲在墙后它发现不了你，但被它盯上以后翻墙甩不掉它。

## 冲锋速度，和玩家奔跑速度（90 × 1.5）一样。
@export var charge_speed := 135.0
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
## 正在往哪边走下平台（0 表示没有）。玩家在正下方时要选定一个方向一直走到边缘，
## 否则每帧重新对准玩家，会在玩家头顶左右抖个不停。
var _drop_direction := 0
## 开始往边缘走时的高度。身体真的降下去了才算开始往下掉，不能只看 is_on_floor()（边缘会闪）。
var _drop_start_y := 0.0


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
		_chase(delta, target != null)
	else:
		_drop_direction = 0
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


func _chase(delta: float, can_see: bool) -> void:
	var offset := _last_seen - global_position
	# 自己站在高处、玩家在正下方：选定当前朝向一直走到平台边缘下去。
	# 单向平台不挡视线，不这样做的话它会停在玩家头顶一直「看得见、够不着」。
	# 身体真的往下降了（比开始走时低 2px 以上）或已经到了玩家的高度才取消，一旦取消就不再恢复。
	# 不能按「离地」取消：走到边缘时 is_on_floor() 会闪一帧 false，它会又站回平台、转头走回去，在平台上来回跑。
	# 落到另一个仍比玩家高的地方（比如墙顶）时，下面的条件会重新选方向。
	if _drop_direction != 0 and (offset.y <= climb_height or global_position.y > _drop_start_y + 2.0):
		_drop_direction = 0
	elif _drop_direction == 0 and is_on_floor() and offset.y > climb_height and absf(offset.x) < climb_reach:
		_drop_direction = facing
		_drop_start_y = global_position.y

	# 选定的方向只用来走到平台边缘；开始往下掉以后（上面已经取消）就在空中照常朝玩家调整，
	# 否则会带着冲锋速度一路飞出去，甚至越过矮墙落到另一边。
	if _drop_direction != 0:
		# 这一边被墙挡住就换另一边下去。
		if is_on_wall():
			_drop_direction = -_drop_direction
		if facing != _drop_direction:
			facing = _drop_direction
			_apply_facing()
		velocity.x = charge_speed * _drop_direction
		return

	# 阈值取这一帧能走的距离：速度快时用固定的小阈值会在目标点前后来回越过。
	if absf(offset.x) > charge_speed * delta:
		var direction := signi(offset.x)
		if direction != facing:
			facing = direction
			_apply_facing()
		velocity.x = charge_speed * facing
	else:
		velocity.x = 0.0
		# 到了最后看见玩家的地方还是看不见，说明跟丢了。
		if not can_see:
			_memory_left = 0.0

	if not is_on_floor() or _jump_timer > 0.0:
		return
	var blocked := is_on_wall() or _wall_ahead()
	var target_above := -offset.y > climb_height and absf(offset.x) < climb_reach
	if blocked or target_above:
		velocity.y = jump_velocity
		_jump_timer = jump_cooldown
