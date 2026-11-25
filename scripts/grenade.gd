class_name Grenade
extends CharacterBody2D
## Grenade: flies in an arc. Hitting a target directly explodes at once; hitting the ground or a wall bounces (bounces times), and after that the next touch explodes;
## it explodes after at most fuse seconds. The explosion hurts enemies within the radius: one hit directly and those at the centre take max_damage,
## less toward the edge (min_damage at the edge), nothing outside. It does not hurt players; enemies shielded by solid objects are unhurt (same rule as Sight).
## One-way platforms behave as for the player: passed through on the way up, landed on on the way down (move_and_collide already respects one-way collision).

## Throw speed (along the aim) and extra upward toss: aim direction × throw_speed + lift upward.
## Throwing straight down (S in the air) adds no upward toss.
@export var throw_speed := 320.0
@export var lift := 440.0
@export var gravity := 1400.0
## Share of speed kept after a bounce.
@export var bounciness := 0.45
## How many bounces before the next hit explodes.
@export var bounces := 1
## Longest time before it explodes no matter what (seconds).
@export var fuse := 1.5
@export var blast_radius := 56.0
## Damage at the blast centre (and on a direct hit) and at the edge of the range; linear with distance in between.
@export var max_damage := 3
## Status applied to whatever it hits (empty for none).
@export var status: StatusEffect
@export var min_damage := 1

## Every grenade in play is in this group (Boss A uses it to dodge grenades).
const GROUP := &"grenades"
## Who this grenade hits: the enemy layer (8) when thrown by the player, the player layer (2) when thrown by enemy F.
## Direct hits and the explosion only look at this layer, so nobody can hurt their own side or themselves.
@export_flags_2d_physics var target_layer := 8
## Which entry of the skin pack draws it (`SkinPack.APPEARANCE_KEYS`). Only the look; the player's and F's grenade rules are exactly the same.
@export var skin_key := &""
## Which event to report when it bursts: the effects layer (`Fx`) draws from it — a grenade is `explosion` (a fireball),
## stage 5's scientist acid flask is `acid_splash` (a splash of green acid). Same rules, different visuals.
@export var blast_event := &"explosion"

## Who threw it (filled in by the weapon slot). An enemy blown up by it rewards this player; in co-op each counts their own.
var shooter: Node

var exploded := false
## Has hit the ground / a platform top (bounced up). From then on it is a grenade "on the ground" bouncing along, which Boss A dodges; bouncing off a wall does not count.
var landed := false

var _age := 0.0
var _bounces_left := 0

@onready var _contact: Area2D = $Contact


## Called by the weapon slot when firing (before being added to the scene tree).
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
	# Anything that can take damage counts as a direct hit (players and enemies both have take_damage with the same name and signature).
	if body.has_method("take_damage"):
		explode(body)


## direct_hit: the target hit directly, which takes full damage.
## Scale the damage by the weapon and attack stat (called by the weapon slot when firing, before joining the tree): centre and edge scale together.
func scale_damage(factor: float) -> void:
	max_damage = maxi(1, roundi(max_damage * factor))
	min_damage = maxi(1, roundi(min_damage * factor))


func explode(direct_hit: Node2D = null) -> void:
	if exploded:
		return
	exploded = true
	GameEvents.report(blast_event, self)
	# Who it reaches and how it falls off live in `Blast`; the suicide robot uses the same
	var space := get_world_2d().direct_space_state
	for victim in Blast.victims(space, global_position, blast_radius, target_layer):
		victim.take_damage(damage_at(victim, direct_hit), global_position, shooter)
		if status != null and victim.has_method(&"apply_status"):
			victim.apply_status(status)
	queue_free()


## How much damage this target takes: a direct hit takes full damage; others by distance to the blast centre, max_damage at the centre and min_damage at the edge.
func damage_at(victim: Node2D, direct_hit: Node2D = null) -> int:
	if victim == direct_hit:
		return max_damage
	return Blast.damage_at(global_position.distance_to(victim.global_position),
		blast_radius, max_damage, min_damage)
