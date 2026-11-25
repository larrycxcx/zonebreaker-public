class_name Bullet
extends Area2D
## A bullet flying in a straight line. It disappears on hitting any collider and damages the target it hits.
## Who it can hit is set by collision_mask in the scene (player bullets hit world+enemy, enemy bullets hit world+player).
## One-way platforms do not stop bullets: the player can pass through them from below and so can bullets, otherwise enemies on platforms could never be shot from below.

@export var speed := 520.0
@export var lifetime := 1.2
@export var damage := 1
## Status applied on hit (empty for none). When a weapon carries a status, the weapon slot fills it in when firing.
@export var status: StatusEffect
## Which entry of the skin pack draws it (`SkinPack.APPEARANCE_KEYS`, same scheme as characters). Only affects the look, not the rules.
@export var skin_key := &""

var direction := Vector2.RIGHT
## Who fired this shot (filled in by the weapon slot). An enemy killed by it rewards this player; in co-op each counts their own.
var shooter: Node

var _age := 0.0


## Called by the weapon slot when firing (before being added to the scene tree).
func launch(direction_: Vector2) -> void:
	direction = direction_


## Scale the damage by the weapon and attack stat (the weapon slot calls this when firing, before adding it to the tree).
func scale_damage(factor: float) -> void:
	damage = maxi(1, roundi(damage * factor))


func _ready() -> void:
	# The shape is a thin horizontal strip, rotated to the flight direction (a vertical strip when shooting up).
	# direction is set before add_child, so the value read here is final.
	rotation = direction.angle()
	# The placeholder strip rotates with the body; the pack's sprite picks a ready-made image per direction (see ProjectileAppearance)
	var visual := Skins.build_appearance(self, skin_key)
	if visual != null:
		visual.aim(direction)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Platform and (body as Platform).one_way:
		return
	if body.has_method("take_damage"):
		# The sound of hitting a character is reported by whoever got hit (enemy_hit / player_hurt etc.).
		body.take_damage(damage, global_position, shooter)
		if status != null and body.has_method(&"apply_status"):
			body.apply_status(status)
	else:
		GameEvents.report(&"bullet_impact", self)
	queue_free()
