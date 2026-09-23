class_name WeaponSlot
extends RefCounted
## 角色身上的一个武器槽：拿着一把 Weapon，记着它的剩余冷却和剩余弹药。
## 角色只管「什么时候开火、朝哪、从哪」，具体发射什么、多快能再发、还剩几发都在这里。

## 弹药变化时发出（无限弹药的武器不会发）。HUD 接这个显示数量。
signal ammo_changed(ammo: int, max_ammo: int)

var weapon: Weapon
var cooldown_left := 0.0
## 拿着它的角色的伤害倍率和冷却倍率（玩家的攻击、速度属性，见 Balance）。敌人没接武器结构，保持 1。
var damage_scale := 1.0
var cooldown_scale := 1.0
## 剩余弹药，-1 表示无限。
var ammo := -1


func _init(weapon_: Weapon = null) -> void:
	if weapon_ != null:
		equip(weapon_)


## 换上一把武器：冷却清零，弹药补满。以后拾取武器、补给就是调这个。
func equip(weapon_: Weapon) -> void:
	weapon = weapon_
	cooldown_left = 0.0
	ammo = weapon.max_ammo
	if ammo >= 0:
		ammo_changed.emit(ammo, weapon.max_ammo)


func tick(delta: float) -> void:
	cooldown_left -= delta


func is_ready() -> bool:
	return weapon != null and cooldown_left <= 0.0 and ammo != 0


## 发射一次：生成发射物、扣弹药、进入冷却、报告事件。不检查冷却和弹药，调用方先看 is_ready()。
func fire(parent: Node, position: Vector2, direction: Vector2, source: Node) -> Node2D:
	var projectile := weapon.projectile.instantiate() as Node2D
	# launch 要在加入场景树之前调：子弹在 _ready 里按方向转自己的外形。
	projectile.call(&"launch", direction)
	# 伤害 = 发射物场景里的伤害 × 武器的 power × 角色的伤害倍率（发射物自己决定怎么乘，手雷有中心和边缘两个数）
	if projectile.has_method(&"scale_damage"):
		projectile.call(&"scale_damage", weapon.power * damage_scale)
	if weapon.status != null and &"status" in projectile:
		projectile.set(&"status", weapon.status)
	# 谁开的火：打死敌人时奖励要记在这个人头上（双人各算各的，见 Progress）
	if &"shooter" in projectile:
		projectile.set(&"shooter", source)
	parent.add_child(projectile)
	projectile.global_position = position
	cooldown_left = weapon.cooldown * cooldown_scale
	if ammo > 0:
		ammo -= 1
		ammo_changed.emit(ammo, weapon.max_ammo)
	GameEvents.report(weapon.fire_event, source)
	return projectile
