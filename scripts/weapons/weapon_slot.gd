class_name WeaponSlot
extends RefCounted
## A weapon slot on a character: holds a Weapon and keeps track of its remaining cooldown and ammo.
## The character only decides "when to fire, which way, from where"; what is fired, how soon it can fire again and how much ammo is left all live here.

## Emitted when ammo changes (never for weapons with unlimited ammo). The HUD shows the count from it.
signal ammo_changed(ammo: int, max_ammo: int)

var weapon: Weapon
var cooldown_left := 0.0
## Damage and cooldown multipliers of the character holding it (the player's attack and speed stats, see Balance). Enemies do not use the weapon system and stay at 1.
var damage_scale := 1.0
var cooldown_scale := 1.0
## Remaining ammo, -1 for unlimited.
var ammo := -1


func _init(weapon_: Weapon = null) -> void:
	if weapon_ != null:
		equip(weapon_)


## Equip a weapon: cooldown cleared, ammo refilled. Weapon pickups and resupplies later call this.
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


## Fire once: spawn the projectile, use ammo, start the cooldown, report the event. Cooldown and ammo are not checked; the caller looks at is_ready() first.
func fire(parent: Node, position: Vector2, direction: Vector2, source: Node) -> Node2D:
	var projectile := weapon.projectile.instantiate() as Node2D
	# launch has to be called before joining the scene tree: bullets rotate their shape to the direction in _ready.
	projectile.call(&"launch", direction)
	# Damage = damage in the projectile scene × the weapon's power × the character's damage multiplier (the projectile decides how to multiply; grenades have two numbers, centre and edge)
	if projectile.has_method(&"scale_damage"):
		projectile.call(&"scale_damage", weapon.power * damage_scale)
	if weapon.status != null and &"status" in projectile:
		projectile.set(&"status", weapon.status)
	# Who fired: an enemy killed by it rewards this player (in co-op each counts their own, see Progress)
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
