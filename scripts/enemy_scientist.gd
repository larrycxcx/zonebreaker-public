class_name EnemyScientist
extends EnemyGrenadier
## 第五关的科学家（5-A / 5-B）：巡逻、往前扔**酸液瓶**（敌人手雷的一种，`acid_flask.tscn`：
## 碰到东西就摔碎、溅开一小团，规则和手雷一样），而且会**变身成变异体**（5-C）。
##
## 变身：站住不动、播 `transform` 那几帧（最后一帧已经是变异体的样子，停在那儿），
## `transform_time` 秒之后原地换成一只变异体（`mutant_scene`），自己悄悄消失——**不给奖励**，
## 奖励在打死变异体的时候给。变身那段时间照样挨打、打死了就是普通的死（有奖励），所以那一下是破绽。
## - 5-A（`transform_on_sight` 关）：**挨打没死、或者玩家贴到 `transform_range` 以内**才变。
##   想省事就在它变之前一口气打死。
## - 5-B（`transform_on_sight` 开）：**一看见玩家就变**，不扔瓶子。

@export_group("Transform")
## 变成什么。留空就不会变身（只会扔瓶子的科学家）。
@export var mutant_scene: PackedScene
## 一看见玩家就变（5-B）；关着就是挨打 / 被贴近才变（5-A）。
@export var transform_on_sight := false
## 玩家贴到多近就变（5-A）。
@export var transform_range := 56.0
## 变身要多久（站着不动、可以挨打的那一段）。
@export var transform_time := 0.9
@export var transform_event := &"chaser_alert"

var _transforming := false
var _transform_left := 0.0


func is_transforming() -> bool:
	return _transforming


func _physics_process(delta: float) -> void:
	if _transforming:
		_transform_left -= delta
		velocity.x = 0.0
		_apply_gravity_only(delta)
		if _transform_left <= 0.0:
			_become_mutant()
		return
	super(delta)
	if mutant_scene == null or health <= 0:
		return
	if transform_on_sight:
		if _sees_a_player():
			start_transform()
	elif _player_within(transform_range):
		start_transform()


## 5-B 一看见就变，所以它不扔瓶子：「交上火」= 看见了，看见了就站定变身。
func throw_target() -> Node2D:
	if transform_on_sight and mutant_scene != null:
		return null
	return super()


func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if health > 0 and not _transforming and mutant_scene != null and not is_queued_for_deletion():
		start_transform()
	elif _transforming and health > 0 and _visual != null and _visual.has_method(&"play_once"):
		# 挨打的那一下受伤帧把变身动画打断了，接着摆回变身的样子
		_visual.call(&"play_once", &"transform", true)


func start_transform() -> void:
	if _transforming or mutant_scene == null:
		return
	_transforming = true
	_transform_left = transform_time
	velocity.x = 0.0
	if _visual != null and _visual.has_method(&"play_once"):
		_visual.call(&"play_once", &"transform", true)
	GameEvents.report(transform_event, self)


func _become_mutant() -> void:
	var mutant := mutant_scene.instantiate() as Node2D
	get_parent().add_child(mutant)
	mutant.global_position = global_position
	mutant.set(&"facing", facing)
	if mutant.has_method(&"face"):
		mutant.call(&"face", facing)
	# 悄悄消失：不 die()，不报死亡、不给奖励（奖励在变异体身上）
	queue_free()


func _sees_a_player() -> bool:
	for player in players_by_distance():
		if within_reach(global_position.distance_to(player.global_position)) \
				and has_line_of_sight(player.body_center()):
			return true
	return false


func _player_within(distance: float) -> bool:
	for player in players_by_distance():
		if player.global_position.distance_to(global_position) <= distance:
			return true
	return false


func _apply_gravity_only(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	move_and_slide()
