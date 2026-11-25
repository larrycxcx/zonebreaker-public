class_name BreakableCrate
extends StaticBody2D
## Breakable crate (2026-10): blocks the way, **a few shots break it open**. 32×24 (the size of the crate in `Chest.png`), solid (world layer) —
## it blocks players, enemies and bullets like a wall, and enemies can hide behind it. After `toughness` hits it falls apart, its collision goes and the way is open.
## Enemy bullets hitting it count too (someone hiding behind it shooting at you may break their own cover).
## Node origin at the top-left corner. One is 24 tall and can be jumped over; a vertical column of `K` in the map becomes a stack (`map_build.py`), and only a stack up to the ceiling truly blocks the way.

@export var skin_key := &"trap_crate"
## Hits to break it (counted in hits, not damage: with a stronger gun the crate still does not break at a touch, so the puzzle keeps its pace).
@export var toughness := 4
## Size of the hitbox (top-left corner at the origin). Crates are `SIZE`; stage 5's gas capsules are 32×48 (set in the scene, along with a matching collision shape).
@export var size := SIZE
## Keep the debris once broken (the node stays, only the collision goes): a shattered gas capsule leaves a ring of glass on the floor that you walk over as usual.
## A crate is deleted entirely once its falling-apart animation has played.
@export var keep_debris := false

const SIZE := Vector2(32, 24)
## Height of the debris (the placeholder draws a strip this tall; the pack's look draws the most broken image).
const DEBRIS_H := 8.0

var hits := 0
var broken := false
var _visual: Node

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Skins.build_appearance(self, skin_key)
	_show()


func take_damage(_amount: int, _source_position := Vector2.INF, _from: Node = null) -> void:
	if broken:
		return
	hits += 1
	if hits >= toughness:
		broken = true
		_shape.set_deferred(&"disabled", true)
		GameEvents.report(&"bullet_impact", self)
	_show()
	if broken and not keep_debris:
		# Removed once the falling-apart animation has played (the look plays it itself; the placeholder block just vanishes)
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(queue_free)


## The look goes by "how many hits so far": 0 = intact, more broken with each hit, falling apart after `broken`.
func damage_stage() -> float:
	return clampf(float(hits) / float(toughness), 0.0, 1.0)


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_damage"):
		_visual.call(&"show_damage", damage_stage(), broken)


func art_rects(_frame: int) -> Array[Rect2]:
	if broken:
		return [Rect2(0.0, size.y - DEBRIS_H, size.x, DEBRIS_H)] if keep_debris else []
	return [Rect2(Vector2.ZERO, size)]
