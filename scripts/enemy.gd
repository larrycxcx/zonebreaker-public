class_name Enemy
extends CharacterBody2D
## 敌人基类：生命值、受击闪白、死亡、重力，以及共用的射击、趴下逻辑。具体行为见子类。

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
## 和玩家的高度差在这个范围内才会开火（子弹只走水平方向）。
@export var vertical_tolerance := 20.0
## 每次开火连发几颗，在 [burst_min, burst_max] 里随机取。都为 1 就是单发。
## fire_interval 从一轮连发的第一颗开始算。
@export_range(1, 10) var burst_min := 1
@export_range(1, 10) var burst_max := 1
## 同一轮连发里相邻两颗子弹的间隔。
@export var burst_gap := 0.15
## 开枪时报告的事件名（素材包按它找声音）：巡逻兵 enemy_shoot，炮台 turret_shoot，E flyer_shoot。
@export var shoot_event := &"enemy_shoot"

@export_group("Prone")
## 玩家在射程内趴下时，敌人也跟着趴下打低处。默认关闭，即只会站着开枪。
@export var can_go_prone := false
## 发现玩家趴下后隔多久才跟着趴下，给玩家留一个躲子弹的窗口。
@export var prone_reaction_time := 0.4

## 趴下后的碰撞体高度，和玩家一样。站着开的枪会从头顶飞过去。
const PRONE_HEIGHT := 4.0
## 物理层 1（world）：地面、平台、墙。
const WORLD_LAYER := 1

var health := 0
var is_prone := false
## 面朝方向，同时决定子弹飞行方向：-1 向左，1 向右。
var facing := -1

var _fire_timer := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _prone_timer := 0.0
var _stand_height := 0.0

@onready var _visual: Node2D = $Visual
## 枪口。新敌人把它直接挂在本体下（`Muzzle`），和外观无关（见 CLAUDE.md「皮肤与素材包」）；
## 老的地面敌人还在 `Visual/Muzzle`，本地 y 坐标为 0——各种地面敌人的碰撞体底边都在原点下方 7px，
## 所以站在同一地面上时出膛高度一致。第 4 步统一挪到本体下。不开枪的敌人（D）没有枪口。
@onready var _muzzle: Marker2D = _find_muzzle()
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _find_muzzle() -> Marker2D:
	var muzzle := get_node_or_null("Muzzle") as Marker2D
	return muzzle if muzzle != null else get_node_or_null("Visual/Muzzle") as Marker2D


func _ready() -> void:
	health = max_health
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


func die() -> void:
	died.emit()
	GameEvents.report(&"enemy_death", self)
	queue_free()


## 射程和高度容差内、并且看得见的玩家，否则返回 null。
func find_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	var offset := player.global_position - global_position
	if absf(offset.x) > detect_range or absf(offset.y) > vertical_tolerance:
		return null
	if not has_line_of_sight(player.body_center()):
		return null
	return player


## 从枪口到 `point` 之间有没有实心障碍（墙、地面、矮通道）挡着。
## 单向平台不挡视线——子弹能穿过去，视线也一样，规则保持一致。
func has_line_of_sight(point: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_sight_origin(), point, WORLD_LAYER)
	var ignored: Array[RID] = []
	# 一条射线最多穿过几块单向平台，给个上限防止意外死循环。
	for i in 8:
		query.exclude = ignored
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var platform := hit["collider"] as Platform
		if platform == null or not platform.one_way:
			return false
		ignored.append(hit["rid"])
	return false


## 视线从哪里发出：有枪口就是枪口（看得见才打得着），没有就是身体中心。
func _sight_origin() -> Vector2:
	return _muzzle.global_position if _muzzle != null else global_position


## 冷却好了就朝 `facing` 方向开一轮火（单发或连发）。`target` 传 null 表示这一帧不该开始新的一轮。
## 一轮连发开始后会打完，即使中途玩家离开了射程。
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
	_fire_one()
	_burst_left = randi_range(burst_min, maxi(burst_min, burst_max)) - 1
	_burst_timer = burst_gap


## 子弹挂在敌人的父节点下，这样敌人死了子弹还能继续飞。
func _fire_one() -> void:
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.direction = shoot_direction()
	get_parent().add_child(bullet)
	bullet.global_position = _muzzle.global_position
	shot_fired.emit()
	GameEvents.report(shoot_event, self)


## 子弹往哪边飞。地面敌人朝面向水平开火；飞行敌人覆盖成向下。
func shoot_direction() -> Vector2:
	return Vector2(facing, 0)


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
