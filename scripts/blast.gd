class_name Blast
## Shared explosion rules: **who gets hit and how much damage each takes**. Grenades and the suicide robot use the same ones.
##
## Rules written twice drift apart sooner or later (one side changes the radius, the other does not), so like `Sight` ("is anything solid between two points")
## they live in one place. Who can be hit is decided by `target_layer`, so neither side can hit its own.


## Targets within reach: inside the radius, able to `take_damage`, and **not shielded by anything solid**.
## Shielded means unhurt — the same rule as an enemy's line of sight (`Sight.is_clear`).
static func victims(space: PhysicsDirectSpaceState2D, at: Vector2, radius: float,
		layer: int) -> Array[Node2D]:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = layer
	var out: Array[Node2D] = []
	for hit in space.intersect_shape(query, 32):
		var victim := hit["collider"] as Node2D
		if victim == null or not victim.has_method("take_damage"):
			continue
		# Already dead and queued for deletion: do not count it again (otherwise the event fires twice and the reward is paid twice)
		if victim is Enemy and (victim as Enemy).health <= 0:
			continue
		if Sight.is_clear(space, at, victim.global_position):
			out.append(victim)
	return out


## Damage at this distance from the centre: **`max_damage` at the centre, `min_damage` at the edge, linear**.
## So standing at the edge only grazes you and the centre is full damage — the way to dodge is distance, not toughing it out.
static func damage_at(distance: float, radius: float, max_damage: int, min_damage: int) -> int:
	var falloff := clampf(distance / maxf(1.0, radius), 0.0, 1.0)
	return roundi(lerpf(max_damage, min_damage, falloff))
