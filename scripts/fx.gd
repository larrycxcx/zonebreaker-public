class_name Fx
extends Node2D
## 特效层：听 `GameEvents`，在对应位置生成短命的占位特效。
##
## 玩法代码一行都不用改——它只管报告「发生了什么」（开枪、打中、撞墙），
## 由这里决定画什么、画在哪。特效场景在关卡里用导出属性指定，第 4 步换素材包时整套替换。
## 特效都是纯显示的 Node2D，没有碰撞，挂在自己下面，关卡一卸载就跟着没了。

## 下面这些是**默认**特效：当前素材包里有同名的特效就用包里的（见 `SkinPack.EFFECT_KEYS`）。
## 开枪时在枪口闪一下。
@export var muzzle_flash_scene: PackedScene
## 子弹打中角色（玩家或敌人）时的火花。
@export var hit_spark_scene: PackedScene
## 子弹打在墙、地面这种实心物体上时的火花。
@export var impact_spark_scene: PackedScene
## 手雷爆炸（大小按爆炸半径缩放）。
@export var explosion_scene: PackedScene

## 哪些事件算「开了一枪」。各角色开枪报告的事件名在场景里设置（`Enemy.shoot_event`），
## 加新敌人时这里要一起加；`test_fx.gd` 会检查关卡里每个敌人的 shoot_event 都在这张表里。
## 特效层所在的分组。倒地的敌人要找个地方播完死亡动画（本体已经删了），就挂到这里来。
const GROUP := &"fx"
const SHOOT_EVENTS: Array[StringName] = [&"player_shoot", &"enemy_shoot", &"turret_shoot", &"flyer_shoot"]
## 这些事件表示「有人挨打了」，在被打的那个身上画火花。
const HIT_EVENTS: Array[StringName] = [&"enemy_hit", &"player_hurt"]


func _ready() -> void:
	add_to_group(GROUP)
	GameEvents.event_happened.connect(_on_event)


func _on_event(event: StringName, source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	if SHOOT_EVENTS.has(event):
		_flash_muzzle(source)
	elif HIT_EVENTS.has(event):
		_spawn(&"hit_spark", hit_spark_scene, _body_center(source))
	elif event == &"bullet_impact":
		# 子弹撞到实心物体时报告，它自己的位置就是命中点；火星朝子弹飞来的方向溅回去。
		var spark := _spawn(&"impact_spark", impact_spark_scene, (source as Node2D).global_position)
		var flew: Variant = source.get(&"direction")
		if spark != null and spark.has_method(&"point") and flew is Vector2:
			spark.call(&"point", -(flew as Vector2))
	elif event == &"explosion":
		# 手雷炸的时候报告，大小照它的爆炸半径来。
		# 有 body_center 的（油桶：原点在桶底）炸在身子正中，手雷这种原点就是中心的照旧
		var blast := _spawn(&"explosion", explosion_scene, _body_center(source))
		if blast != null:
			blast.set(&"radius", source.get(&"blast_radius"))
	elif event == &"ultimate_blast":
		# 终极武器定格结束：在它这一下打的每个敌人身上各炸一团（报告时敌人还没被消灭，读得到位置）。
		# 只有终极武器本身带着 targets；别处（比如测音效时）拿别的对象报告这个事件，就没有要画的
		var targets: Variant = source.get(&"targets")
		if not targets is Array:
			return
		for target: Variant in targets:
			if not is_instance_valid(target):
				continue
			var at: Vector2 = target.body_center() if target.has_method(&"body_center") else target.global_position
			var blast := _spawn(&"explosion", explosion_scene, at)
			if blast != null:
				blast.set(&"radius", source.get(&"blast_radius"))


## 枪口闪光：开枪的人自己记着这一枪从哪出膛、朝哪打（last_muzzle_position / last_shot_direction）。
func _flash_muzzle(source: Node) -> void:
	var position_: Vector2 = source.get(&"last_muzzle_position")
	var direction: Vector2 = source.get(&"last_shot_direction")
	var flash := _spawn(&"muzzle_flash", muzzle_flash_scene, position_)
	if flash == null or direction == Vector2.ZERO:
		return
	# 素材包的像素图不能转 45°，有 point() 就让它挑那个方向画好的图；占位方块照旧整个转过去
	if flash.has_method(&"point"):
		flash.call(&"point", direction)
	else:
		flash.rotation = direction.angle()


## 身体中心：玩家趴下时中心更低，有这个方法就用它。
func _body_center(source: Node) -> Vector2:
	if source.has_method("body_center"):
		return source.call("body_center")
	return (source as Node2D).global_position


## 生成一个特效：当前素材包里有这个键就用包里的，没有就用节点上配的默认场景。
func _spawn(key: StringName, fallback: PackedScene, position_: Vector2) -> Node2D:
	var scene := Skins.effect(key, fallback)
	if scene == null:
		return null
	var effect := scene.instantiate() as Node2D
	add_child(effect)
	effect.global_position = position_
	return effect
