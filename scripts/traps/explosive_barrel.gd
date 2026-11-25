class_name ExplosiveBarrel
extends StaticBody2D
## Explosive barrel (a trap the user asked for in 2026-10): placed next to enemies, **it explodes when shot**, hitting nearby enemies — **and the player too**.
##
## - It is on the **enemy layer** (it blocks nobody: neither the players' nor the enemies' mask includes that layer), so **the players' bullets and grenades can hit it,
## but enemy bullets cannot** — enemies never blow it up themselves. The player's Hurtbox only reacts to `Enemy`, so touching it does no damage.
## - One shot sets it off. The explosion is the grenade's (`Blast`: only things within the radius and not shielded by anything solid are hit, `max_damage` at the centre
## falling linearly to `min_damage` at the edge), **hitting enemies and players alike** — keep your distance when setting it off. The visual is drawn by `Fx` from the `explosion` event.
## - Neighbouring barrels are on the enemy layer too and get hit as well — **chain reactions**.
## - Enemies it kills are credited to **the player who fired** (passed all the way down as the third argument of `take_damage`).
## The node origin is **the middle of the barrel** (like enemies: `Blast` measures distance and sight from the origin; an origin on the floor would have the ray graze the floor and get blocked).

@export var skin_key := &"trap_barrel"
@export var blast_radius := 56.0
@export var max_damage := 80
@export var min_damage := 30

## The hitbox matches the barrel body in the art (18×22; the top 4 rows are empty)
const SIZE := Vector2(18, 22)
const ENEMY_LAYER := 8
const PLAYER_LAYER := 2

var exploded := false
var _shooter: Node = null


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	Skins.build_appearance(self, skin_key)


func take_damage(_amount: int, _source_position := Vector2.INF, from: Node = null) -> void:
	if exploded:
		return
	exploded = true
	_shooter = from
	# Once it bursts it should not stop bullets any more (later bullets in the same frame pass through instead of hitting a barrel that is gone)
	collision_layer = 0
	# Shapes cannot be queried inside a physics callback (`Blast.victims` has to), so move it to the end of this frame
	_explode.call_deferred()


func body_center() -> Vector2:
	return global_position


func _explode() -> void:
	var at := body_center()
	GameEvents.report(&"explosion", self)
	var space := get_world_2d().direct_space_state
	for victim in Blast.victims(space, at, blast_radius, ENEMY_LAYER | PLAYER_LAYER):
		if victim == self:
			continue
		var hurt := Blast.damage_at(at.distance_to(victim.global_position), blast_radius, max_damage, min_damage)
		# Chain: other barrels take_damage too, still passing on the player who fired
		victim.take_damage(roundi(hurt * Stage.damage_scale()), at, _shooter if _shooter != null else self)
	queue_free()


## The shape drawn by the placeholder look (`TrapBlocks`): a red barrel.
func art_rects(_frame: int) -> Array[Rect2]:
	return [Rect2(-SIZE / 2.0, SIZE)]
