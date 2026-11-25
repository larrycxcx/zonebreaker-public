class_name PoisonDrip
extends CharacterBody2D
## A drop of poison (dripped by stage 5's ceiling emitter 5-F): it falls and **bursts into a poison cloud on touching the ground, a one-way ledge or a player**
## (`PoisonCloud`), and is gone. The drop itself hurts nobody — the cloud does (poison).
## If it falls out of the stage, so be it (2-second safety limit). It only reacts to the world layer (one-way ledges catch it too: falling down, `move_and_collide` already follows the one-way rule).

@export var cloud_scene: PackedScene = preload("res://scenes/poison_cloud.tscn")
@export var skin_key := &"poison_drip"
@export var gravity := 900.0
@export var start_speed := 60.0
## How high above the landing point the cloud's centre goes (the cloud's radius is 24; at this height it covers a standing player's lower body).
@export var cloud_lift := 18.0
const SIZE := Vector2(8, 12)
const LIFETIME := 2.0

var burst := false
var _age := 0.0
var _visual: Node


func launch(_direction: Vector2) -> void:
	velocity = Vector2(0.0, start_speed)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	_visual = Skins.build_appearance(self, skin_key)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	velocity.y += gravity * delta
	var hit := move_and_collide(velocity * delta)
	if hit != null:
		pop(global_position + Vector2(0.0, SIZE.y / 2.0))
		return
	var box := Rect2(global_position - SIZE / 2.0, SIZE)
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.is_alive() and player.hit_box().intersects(box):
			pop(Vector2(global_position.x, player.global_position.y + 16.0))
			return


## Burst: put a poison cloud above the landing point (`floor` is the world position of the landing line).
func pop(floor: Vector2) -> void:
	if burst:
		return
	burst = true
	var cloud := cloud_scene.instantiate() as Node2D
	get_parent().add_child(cloud)
	cloud.global_position = floor - Vector2(0.0, cloud_lift)
	queue_free()
