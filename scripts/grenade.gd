class_name Grenade
extends CharacterBody2D
## 手雷：沿抛物线飞。直接碰到敌人立刻爆炸；撞到地面、墙会弹一下（bounces 次），之后再碰到就爆炸；
## 最长 fuse 秒强制爆炸。爆炸伤害半径内的敌人：直接砸中的、以及在爆炸中心的受 max_damage，
## 越往边缘越少（边缘 min_damage），范围外没有伤害。不伤玩家；实心物体挡住的敌人不受伤（规则同 Sight）。
## 单向平台和玩家一样：往上飞时穿过、往下落时落在上面（move_and_collide 本身就遵守单向碰撞）。

## 扔出去的速度（沿瞄准方向）和额外的上抛速度：瞄准方向 × throw_speed + 向上 lift。
## 往正下方丢（空中按 S）时不加上抛。
@export var throw_speed := 160.0
@export var lift := 220.0
@export var gravity := 700.0
## 反弹后保留多少速度。
@export var bounciness := 0.45
## 能弹几次，之后再撞到东西就爆炸。
@export var bounces := 1
## 最长多久一定爆炸（秒）。
@export var fuse := 1.5
@export var blast_radius := 28.0
## 爆炸中心（和直接砸中）的伤害，以及范围边缘的伤害，中间按距离线性过渡。
@export var max_damage := 3
@export var min_damage := 1
## 爆炸的样子（占位美术），只管显示。
@export var explosion_scene: PackedScene

## 场上的手雷都在这个组里（Boss A 躲手雷时靠它找）。
const GROUP := &"grenades"
## 物理层 4（enemy）的位掩码：爆炸只找敌人，所以不会炸到玩家自己。
const ENEMY_LAYER := 8

var exploded := false
## 撞到过地面/平台顶面（弹起来过）。之后它就是「在地上」贴地弹跳的手雷，Boss A 会躲；撞墙反弹不算。
var landed := false

var _age := 0.0
var _bounces_left := 0

@onready var _contact: Area2D = $Contact


## 武器槽发射时调用（在加入场景树之前）。
func launch(direction: Vector2) -> void:
	velocity = direction * throw_speed
	if direction.y < 0.9:
		velocity.y -= lift
	_bounces_left = bounces


func _ready() -> void:
	add_to_group(GROUP)
	_contact.body_entered.connect(_on_contact)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= fuse:
		explode()
		return
	velocity.y += gravity * delta
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	if _bounces_left > 0:
		_bounces_left -= 1
		velocity = velocity.bounce(collision.get_normal()) * bounciness
		if collision.get_normal().y < -0.7:
			landed = true
		GameEvents.report(&"grenade_bounce", self)
	else:
		explode()


func _on_contact(body: Node2D) -> void:
	if body is Enemy:
		explode(body as Enemy)


## direct_hit：直接砸中的那个敌人，受满伤害。
func explode(direct_hit: Enemy = null) -> void:
	if exploded:
		return
	exploded = true
	GameEvents.report(&"explosion", self)
	var space := get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = blast_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = ENEMY_LAYER
	for hit in space.intersect_shape(query, 32):
		var enemy := hit["collider"] as Enemy
		if enemy == null or enemy.health <= 0:
			continue
		# 隔着墙的敌人炸不到：从爆炸中心到敌人身体中心之间要没有实心物体。
		if Sight.is_clear(space, global_position, enemy.global_position):
			enemy.take_damage(damage_at(enemy, direct_hit), global_position)
	if explosion_scene != null:
		var effect := explosion_scene.instantiate() as Node2D
		effect.set(&"radius", blast_radius)
		get_parent().add_child(effect)
		effect.global_position = global_position
	queue_free()


## 这个敌人该受多少伤害：直接砸中的满伤害；其余按到爆炸中心的距离，中心 max_damage、边缘 min_damage。
func damage_at(enemy: Enemy, direct_hit: Enemy = null) -> int:
	if enemy == direct_hit:
		return max_damage
	var falloff := clampf(global_position.distance_to(enemy.global_position) / blast_radius, 0.0, 1.0)
	return roundi(lerpf(max_damage, min_damage, falloff))
