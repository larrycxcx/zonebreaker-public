class_name PoisonCloud
extends Node2D
## 一团毒雾（2026-11，第五关）：在原地停一会儿，**站在里面的玩家中毒**（`status/poison.tres`），
## 出来之后中毒还会持续一阵（状态自己的持续时间）。待在里面就一直刷新，不叠加伤害。
## 5_f（天花板上的发射器）滴下来的毒液落地就炸成一团这个；以后别的东西也能放。
##
## 节点原点是毒雾的中心。判定是一个圆（`radius`），和玩家的判定框相交就算在里面。
## 外观只管画（素材包是 `Acid2` 那团慢慢散开的毒雾，占位是一个半透明的绿圈），玩法和外观无关。
## 只伤玩家；不挡人、不挡子弹（没有碰撞体）。

const GROUP := &"poison_clouds"

@export var skin_key := &"poison_cloud"
@export var status: StatusEffect = preload("res://status/poison.tres")
## 判定圆的半径：素材里毒雾散开到最大时直径约 48。
@export var radius := 24.0
## 停多久（秒）。
@export var lifetime := 1.8

var age := 0.0
var _visual: Node


func _ready() -> void:
	add_to_group(GROUP)
	_visual = Skins.build_appearance(self, skin_key)
	_show()


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.is_alive() and touches(player.hit_box()):
			player.apply_status(status)
	_show()


## 这个框和毒雾那个圆相交吗（世界坐标）。
func touches(box: Rect2) -> bool:
	var nearest := Vector2(clampf(global_position.x, box.position.x, box.end.x),
		clampf(global_position.y, box.position.y, box.end.y))
	return nearest.distance_to(global_position) <= radius


## 散到几成了（0 刚炸开 → 1 散完）。
func progress() -> float:
	return clampf(age / lifetime, 0.0, 1.0)


## 占位色块（`TrapBlocks`）不画圆，这里给它一块方的；外观有 `show_progress` 的走那条。
func art_rects(_frame: int) -> Array[Rect2]:
	return [Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0)]


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_progress"):
		_visual.call(&"show_progress", progress())
