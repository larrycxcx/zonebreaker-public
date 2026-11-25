class_name Sight
extends RefCounted
## "Is anything solid between two points": enemy sight and grenade blast reach both use this, so the rule stays the same —
## solid things such as the ground, walls and crawl passages block; one-way platforms do not (bullets and players can pass through them from below).

## Physics layer 1 (world): ground, platforms, walls.
const WORLD_LAYER := 1


static func is_clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_LAYER)
	var ignored: Array[RID] = []
	# At most how many one-way platforms one ray passes through; a cap against accidental endless loops.
	for i in 8:
		query.exclude = ignored
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var platform := hit["collider"] as Platform
		if platform == null or not platform.one_way:
			return false
		ignored.append(hit["rid"])
	return false


## Going from from toward to, where is **the first solid object** (same rule as above: one-way platforms do not block); to if nothing is in the way.
## The basement boss's laser uses it: it stops at walls and passes through one-way platforms.
static func first_solid(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_LAYER)
	var ignored: Array[RID] = []
	for i in 8:
		query.exclude = ignored
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return to
		var platform := hit["collider"] as Platform
		if platform == null or not platform.one_way:
			return hit["position"]
		ignored.append(hit["rid"])
	return to
