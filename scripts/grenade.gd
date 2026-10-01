class_name Grenade
extends CharacterBody2D
## 手雷：沿抛物线飞。直接碰到目标立刻爆炸；撞到地面、墙会弹一下（bounces 次），之后再碰到就爆炸；
## 最长 fuse 秒强制爆炸。爆炸伤害半径内的敌人：直接砸中的、以及在爆炸中心的受 max_damage，
## 越往边缘越少（边缘 min_damage），范围外没有伤害。不伤玩家；实心物体挡住的敌人不受伤（规则同 Sight）。
## 单向平台和玩家一样：往上飞时穿过、往下落时落在上面（move_and_collide 本身就遵守单向碰撞）。

## 扔出去的速度（沿瞄准方向）和额外的上抛速度：瞄准方向 × throw_speed + 向上 lift。
## 往正下方丢（空中按 S）时不加上抛。
@export var throw_speed := 320.0
@export var lift := 440.0
@export var gravity := 1400.0
## 反弹后保留多少速度。
@export var bounciness := 0.45
## 能弹几次，之后再撞到东西就爆炸。
@export var bounces := 1
## 最长多久一定爆炸（秒）。
@export var fuse := 1.5
@export var blast_radius := 56.0
## 爆炸中心（和直接砸中）的伤害，以及范围边缘的伤害，中间按距离线性过渡。
@export var max_damage := 3
## 炸到谁就给谁挂上的异常状态（留空就没有）。
@export var status: StatusEffect
@export var min_damage := 1

## 场上的手雷都在这个组里（Boss A 躲手雷时靠它找）。
const GROUP := &"grenades"
## 这颗手雷打谁：玩家扔的填 enemy 层（8），敌人 F 扔的填 player 层（2）。
## 直接命中和爆炸都只找这一层，所以谁也炸不到自己人、炸不到自己。
@export_flags_2d_physics var target_layer := 8
## 素材包里用哪一项画它（`SkinPack.APPEARANCE_KEYS`）。只管长什么样，玩家和 F 的手雷规则完全一样。
@export var skin_key := &""

## 谁扔的（武器槽发射时填）。敌人被炸死时奖励记在这个人头上，双人各算各的。
var shooter: Node

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
	Skins.build_appearance(self, skin_key)
	_contact.collision_mask = target_layer
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
	# 能受伤害的都算直接命中（玩家和敌人都有同名同签名的 take_damage）。
	if body.has_method("take_damage"):
		explode(body)


## direct_hit：直接砸中的那个目标，受满伤害。
## 按武器和攻击力放大伤害（武器槽在发射时调，加入场景树之前）：中心和边缘一起放大。
func scale_damage(factor: float) -> void:
	max_damage = maxi(1, roundi(max_damage * factor))
	min_damage = maxi(1, roundi(min_damage * factor))


func explode(direct_hit: Node2D = null) -> void:
	if exploded:
		return
	exploded = true
	GameEvents.report(&"explosion", self)
	# 炸得到谁、怎么衰减都在 `Blast` 里，自爆的机器人用的是同一套
	var space := get_world_2d().direct_space_state
	for victim in Blast.victims(space, global_position, blast_radius, target_layer):
		victim.take_damage(damage_at(victim, direct_hit), global_position, shooter)
		if status != null and victim.has_method(&"apply_status"):
			victim.apply_status(status)
	queue_free()


## 这个目标该受多少伤害：直接砸中的满伤害；其余按到爆炸中心的距离，中心 max_damage、边缘 min_damage。
func damage_at(victim: Node2D, direct_hit: Node2D = null) -> int:
	if victim == direct_hit:
		return max_damage
	return Blast.damage_at(global_position.distance_to(victim.global_position),
		blast_radius, max_damage, min_damage)
