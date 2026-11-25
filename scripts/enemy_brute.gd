class_name EnemyBrute
extends EnemyHammer
## 3-D Brute: a melee enemy that **soaks damage from the front**. Breastplate and both pauldrons are in front, so **hits from the front do half damage**,
## hits from behind do full damage.
##
## It **does not charge** (the scene sets `charge_speed` equal to `move_speed`): just a wall slowly pressing in,
## and positioning is entirely up to the player. Three ways to fight it: get behind it, jump over it, or **lob a grenade over its head**
## — grenades fly in an arc and land behind it, which is a full-damage hit.
##
## All of "walk up and swing" belongs to `EnemyHammer` (patrol, turning, wind-up, damage on the frame the swing lands);
## this only adds the frontal damage reduction.

@export_group("Armour")
## Damage multiplier for hits from the front. 1.0 = no armour.
@export_range(0.0, 1.0) var front_armour := 0.5


## Damage from the front is halved. **Unknown sources are not reduced** (`Vector2.INF`, e.g. damage over time, falling out of the stage) —
## the armour stops things that hit it, not all damage.
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	if is_from_the_front(source_position):
		amount = maxi(1, roundi(amount * front_armour))
	super(amount, source_position, from)


## Did this hit come from the side it faces.
func is_from_the_front(source_position: Vector2) -> bool:
	if source_position == Vector2.INF:
		return false
	var side := signi(source_position.x - global_position.x)
	return side != 0 and side == facing
