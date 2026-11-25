class_name VisualFlip
extends RefCounted
## The shared way to flip appearances left / right: **do not use a negative `scale`**.
##
## A negative scale makes the Controls under `Visual` (the ColorRects of the placeholder art) compute a wrong draw rect
## (the position of `get_global_rect()` is off by a whole body width and the height is negative), and the engine culls by that rect,
## so in some positions the whole appearance is treated as "off screen" and not drawn — showing up as Boss A occasionally vanishing mid-jump.
## Every character flipped this way; Boss A, the biggest and highest jumper, just exposed it.
##
## Instead the scale stays positive and the horizontal position of each child of `Visual` is mirrored:
## blocks (Control) are mirrored as `-x - width` (the whole rectangle is mirrored), points such as muzzles (Node2D) as `-x`.
## In scenes, everything is always laid out **facing right**.


## Record the original horizontal position of each child of Visual; call once before flipping (usually in _ready).
static func capture(visual: Node2D) -> Dictionary:
	var bases := {}
	for child in visual.get_children():
		if child is Control:
			bases[child] = (child as Control).position.x
		elif child is Node2D:
			bases[child] = (child as Node2D).position.x
	return bases


## Lay out by facing: facing = 1 uses the original positions, facing = -1 mirrors them.
static func apply(bases: Dictionary, facing: int) -> void:
	for child in bases:
		var base: float = bases[child]
		if child is Control:
			var rect := child as Control
			rect.position.x = base if facing > 0 else -base - rect.size.x
		else:
			(child as Node2D).position.x = base if facing > 0 else -base


## Point the turning gun barrel (placeholder art) at direction.
## In the scene the barrel is laid out "facing right, sticking out of the body"; it pivots on the end next to the body, which is on the rectangle's right side when facing left.
static func aim_gun(gun: Control, facing: int, direction: Vector2) -> void:
	gun.pivot_offset = Vector2(0.0 if facing > 0 else gun.size.x, gun.size.y / 2.0)
	# When facing left the rectangle itself is already mirrored (its own +x points at the body), so it turns another half circle.
	gun.rotation = direction.angle() - (0.0 if facing > 0 else PI)
