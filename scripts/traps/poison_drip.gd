class_name PoisonDrip
extends CharacterBody2D
## 一滴毒液（第五关天花板上的发射器 5-F 滴下来的）：往下掉，**碰到地面、单向台子或者玩家就炸成一团毒雾**
## （`PoisonCloud`），自己没了。本身不伤人——伤人的是那团毒雾（中毒）。
## 掉得出关卡就算了（2 秒保底）。只认 world 层（单向台子也接得住：往下落时 `move_and_collide` 本来就守单向规则）。

@export var cloud_scene: PackedScene = preload("res://scenes/poison_cloud.tscn")
@export var skin_key := &"poison_drip"
@export var gravity := 900.0
@export var start_speed := 60.0
## 毒雾的中心摆在落点上面多高（毒雾半径 24，中心离地这么高正好糊住站着的人的下半身）。
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


## 炸开：在落点（`floor` 是落点那条线的世界坐标）上面放一团毒雾。
func pop(floor: Vector2) -> void:
	if burst:
		return
	burst = true
	var cloud := cloud_scene.instantiate() as Node2D
	get_parent().add_child(cloud)
	cloud.global_position = floor - Vector2(0.0, cloud_lift)
	queue_free()
