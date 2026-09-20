class_name Enemy
extends CharacterBody2D
## 敌人基类：生命值、受击闪白、死亡、重力，以及共用的射击、趴下逻辑。具体行为见子类。
## 直接继承它的是普通敌人（A/B/C/D/E/炮台）；Boss 继承 Boss（scripts/boss.gd）。

signal died
## 每射出一颗子弹发一次（连发时每颗都发）。第 3 步的枪口闪光、音效可以接在这上面。
signal shot_fired

@export var max_health := 2
## 碰到玩家时对玩家造成的伤害。
@export var contact_damage := 1
@export var gravity := 900.0
@export var max_fall_speed := 400.0

@export_group("Shooting")
## 留空表示这个敌人不会射击。
@export var bullet_scene: PackedScene
@export var fire_interval := 1.4
@export var detect_range := 150.0
## 和玩家的高度差在这个范围内就水平开火。
@export var vertical_tolerance := 20.0
## 每次开火连发几颗，在 [burst_min, burst_max] 里随机取。都为 1 就是单发。
## fire_interval 从一轮连发的第一颗开始算。
@export_range(1, 10) var burst_min := 1
@export_range(1, 10) var burst_max := 1
## 同一轮连发里相邻两颗子弹的间隔。
@export var burst_gap := 0.15
## 开枪时报告的事件名（素材包按它找声音）：巡逻兵 enemy_shoot，炮台 turret_shoot，E flyer_shoot。
@export var shoot_event := &"enemy_shoot"

@export_group("Diagonal")
## 能不能站定斜上/斜下开枪（B、C、炮台）。玩家不在同一高度、而在斜上/斜下方向时，
## 巡逻兵会停下脚步、炮台转向，瞄准 diagonal_aim_time 秒后朝 45° 开火；玩家回到水平方向就恢复原样。
@export var can_aim_diagonally := false
## 转到斜向后先瞄准多久才开第一枪（像魂斗罗的炮台要转过来），给玩家反应的时间。
@export var diagonal_aim_time := 0.3
## 瞄准时要转动的枪管（占位美术），留空就不转。放在场景里设置，换皮肤时不用改代码。
@export var gun_visual: NodePath

@export_group("Prone")
## 玩家在射程内趴下时，敌人也跟着趴下打低处。默认关闭，即只会站着开枪。
@export var can_go_prone := false
## 发现玩家趴下后隔多久才跟着趴下，给玩家留一个躲子弹的窗口。
@export var prone_reaction_time := 0.4

## 趴下后的碰撞体高度，和玩家一样。站着开的枪会从头顶飞过去。
const PRONE_HEIGHT := 4.0
## 玩家所在方向偏离水平线的角度在这个区间里才斜着打（子弹固定走 45°）；更平的算水平、更陡的不打。
const DIAGONAL_MIN_ANGLE := 22.5
const DIAGONAL_MAX_ANGLE := 67.5
## 斜向出膛点，相对身体中心（朝右时；朝左 x 取反）。由代码算，不挂在 Visual 下。
## 斜下的 y 不能太大：站在地上时子弹一出膛就会嵌进地面。
const DIAGONAL_UP_MUZZLE := Vector2(10, -8)
const DIAGONAL_DOWN_MUZZLE := Vector2(10, 3)

## 瞄准方向。
enum Aim { LEVEL, DIAGONAL_UP, DIAGONAL_DOWN }

## 所有敌人都在这个组里（终极武器靠它找屏幕内的敌人）。
const GROUP := &"enemies"

var health := 0
var is_prone := false
var aim := Aim.LEVEL
## 最近一颗子弹的方向和出膛点（测试和枪口闪光读它，见 fx.gd）。
var last_shot_direction := Vector2.ZERO
var last_muzzle_position := Vector2.ZERO
## 面朝方向，同时决定子弹飞行方向：-1 向左，1 向右。
var facing := -1

var _fire_timer := 0.0
var _burst_left := 0
var _burst_timer := 0.0
## 一轮连发开始时锁定的方向和瞄准：剩下的子弹沿用它们。
## 否则水平连发打到一半玩家跳上平台，剩下的子弹会直接斜着打出去，跳过斜向的瞄准时间。
var _burst_direction := Vector2.ZERO
var _burst_aim := Aim.LEVEL
var _prone_timer := 0.0
var _stand_height := 0.0
## 当前瞄准方向已经保持了多久。
var _aim_timer := 0.0
## Visual 下每个子节点朝右时的横向位置，翻转时按它镜像（见 VisualFlip）。
var _visual_bases := {}

@onready var _visual: Node2D = $Visual
## 枪口 Marker，挂在**本体**下（不在 `Visual` 里）：它只给出「伸出去多远」这个偏移，
## 实际出膛高度按碰撞体中心算（见 `level_muzzle_position()`），所以和外观长什么样、压没压扁都无关。
## 不开枪的敌人（D）没有枪口。
@onready var _muzzle: Marker2D = get_node_or_null("Muzzle") as Marker2D
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health
	_visual_bases = VisualFlip.capture(_visual)
	_apply_visual_facing()
	_stand_height = (_shape.shape as RectangleShape2D).size.y


## 被子弹调用（Bullet 通过 has_method("take_damage") 找到它）。
## `_source_position` 目前用不到，只为和 Player.take_damage 保持同样的签名。
func take_damage(amount: int, _source_position := Vector2.INF) -> void:
	if health <= 0:
		return
	health -= amount
	if health <= 0:
		die()
	else:
		_flash()
		GameEvents.report(&"enemy_hit", self)


## 被终极武器打中：普通敌人直接消灭（不管血量）。Boss 覆盖成只受伤害。
func hit_by_ultimate() -> void:
	die()


## 身体原点在不在屏幕可见范围内（终极武器、Boss 出场用）。
func is_on_screen() -> bool:
	var viewport := get_viewport()
	var visible := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	return visible.has_point(global_position)


func die() -> void:
	died.emit()
	GameEvents.report(&"enemy_death", self)
	queue_free()


## 打得着、并且看得见的玩家，否则返回 null（「打得着」见 aim_for()）。
func find_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	if aim_for(player) < 0:
		return null
	if not has_line_of_sight(player.body_center()):
		return null
	return player


## 对着这个目标该用哪个瞄准方向；打不着返回 -1。
## 水平：水平距离在射程内、高度差在 vertical_tolerance 内（原来的规则）。
## 斜向（can_aim_diagonally 才有）：直线距离在射程内，偏离水平线 22.5°~67.5°。
func aim_for(target: Node2D) -> int:
	var offset := target.global_position - global_position
	if absf(offset.x) <= detect_range and absf(offset.y) <= vertical_tolerance:
		return Aim.LEVEL
	if not can_aim_diagonally or offset.length() > detect_range:
		return -1
	var angle := rad_to_deg(atan2(absf(offset.y), absf(offset.x)))
	if angle < DIAGONAL_MIN_ANGLE or angle > DIAGONAL_MAX_ANGLE:
		return -1
	return Aim.DIAGONAL_UP if offset.y < 0.0 else Aim.DIAGONAL_DOWN


## 子类每帧拿当前目标调用：更新瞄准方向，返回这一帧可以开火的目标。
## 刚转到斜向时要先瞄准 diagonal_aim_time 秒，这段时间返回 null（不开火）。
func update_aim(delta: float, target: Node2D) -> Node2D:
	var wanted: int = Aim.LEVEL if target == null else aim_for(target)
	if wanted < 0:
		wanted = Aim.LEVEL
		target = null
	if wanted != aim:
		aim = wanted as Aim
		_aim_timer = 0.0
		_show_aim()
	else:
		_aim_timer += delta
	if target != null and aim != Aim.LEVEL and _aim_timer < diagonal_aim_time:
		return null
	return target


func is_aiming_diagonally() -> bool:
	return aim != Aim.LEVEL


## 按当前朝向摆放外观。**不要用负的 scale 翻转**，原因见 VisualFlip。
func _apply_visual_facing() -> void:
	VisualFlip.apply(_visual_bases, facing)
	_show_aim()


## 占位美术：把枪管转到开火方向。
func _show_aim() -> void:
	var gun := get_node_or_null(gun_visual) as Control
	if gun == null:
		return
	VisualFlip.aim_gun(gun, facing, shoot_direction())


## 从枪口到 `point` 之间有没有实心障碍（墙、地面、矮通道）挡着；单向平台不挡。规则见 Sight。
func has_line_of_sight(point: Vector2) -> bool:
	return Sight.is_clear(get_world_2d().direct_space_state, _sight_origin(), point)


## 视线从哪里发出：枪口（看得见才打得着）。没有枪口的（D）就从身体中心发出。
func _sight_origin() -> Vector2:
	return level_muzzle_position()


## 冷却好了就朝当前瞄准方向开一轮火（单发或连发）。`target` 传 null 表示这一帧不该开始新的一轮。
## 一轮连发开始后会按开始时的方向打完，即使中途玩家离开了射程或换了方位。
func try_shoot(delta: float, target: Node2D) -> void:
	_fire_timer -= delta
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_timer = burst_gap
		return
	if target == null or bullet_scene == null or _fire_timer > 0.0:
		return
	_fire_timer = fire_interval
	_burst_direction = shoot_direction()
	_burst_aim = aim
	_fire_one()
	_burst_left = randi_range(burst_min, maxi(burst_min, burst_max)) - 1
	_burst_timer = burst_gap


## 子弹挂在敌人的父节点下，这样敌人死了子弹还能继续飞。
func _fire_one() -> void:
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.direction = _burst_direction
	last_shot_direction = bullet.direction
	last_muzzle_position = _muzzle_position()
	get_parent().add_child(bullet)
	bullet.global_position = last_muzzle_position
	shot_fired.emit()
	GameEvents.report(shoot_event, self)


## 子弹往哪边飞：按瞄准方向，水平或 45° 斜上/斜下；飞行敌人覆盖成向下。
func shoot_direction() -> Vector2:
	match aim:
		Aim.DIAGONAL_UP:
			return Vector2(facing, -1).normalized()
		Aim.DIAGONAL_DOWN:
			return Vector2(facing, 1).normalized()
	return Vector2(facing, 0)


## 出膛点（按这一轮锁定的瞄准）：水平用枪口，斜向由代码按身体中心算。
func _muzzle_position() -> Vector2:
	if _burst_aim == Aim.LEVEL:
		return level_muzzle_position()
	var offset := DIAGONAL_UP_MUZZLE if _burst_aim == Aim.DIAGONAL_UP else DIAGONAL_DOWN_MUZZLE
	return global_position + Vector2(offset.x * signf(_burst_direction.x), offset.y)


## 碰撞体中心的世界坐标。趴下时碰撞体压低、中心跟着下来，所以判定点都按它算。
func body_center() -> Vector2:
	return _shape.global_position


## 水平方向的出膛点（E 的竖直向下也走这里）：**碰撞体中心** + 枪口 Marker 的偏移，朝左时 x 取反。
## 按碰撞体算而不是直接读 Marker 的世界坐标，是为了让「趴下时子弹贴地飞」这条规则
## 依赖碰撞体高度、而不是依赖占位方块被压扁——换成精灵图以后规则不会跟着变。
func level_muzzle_position() -> Vector2:
	if _muzzle == null:
		return body_center()
	return body_center() + Vector2(_muzzle.position.x * facing, _muzzle.position.y)


## 子类每帧拿当前瞄准的目标调用：目标趴着就隔 prone_reaction_time 跟着趴下，否则马上站起来。
func update_prone(delta: float, target: Node2D) -> void:
	var player := target as Player
	if not (can_go_prone and player != null and player.is_crouching):
		_prone_timer = 0.0
		if is_prone:
			set_prone(false)
		return
	if is_prone:
		return
	_prone_timer += delta
	if _prone_timer >= prone_reaction_time:
		set_prone(true)


## 和玩家下蹲同一套做法：碰撞体压低并下移让脚底不动，Visual 整体压扁，
## 枪口是 Visual 的子节点，会跟着降到贴地的高度。
func set_prone(value: bool) -> void:
	if value and not is_prone:
		GameEvents.report(&"enemy_prone", self)
	is_prone = value
	var height := PRONE_HEIGHT if value else _stand_height
	var lowered := (_stand_height - height) / 2.0
	(_shape.shape as RectangleShape2D).size.y = height
	_shape.position.y = lowered
	_visual.scale.y = height / _stand_height
	_visual.position.y = lowered


func _flash() -> void:
	_visual.modulate = Color(2.0, 2.0, 2.0)
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.12)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
