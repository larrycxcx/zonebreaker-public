class_name Ultimate
extends Node2D
## 终极武器的效果（瞬时发动，用 weapons/ultimate.tres 的武器槽发射出来，所以次数、冷却都走武器结构）。
##
## 发动的瞬间：清除所有敌人子弹，记下此刻屏幕内的敌人，给玩家无敌，然后暂停整个场景树——
## 玩家、敌人、子弹全部定格 freeze_time 秒。时间到了恢复运行，同时消灭刚才记下的那些敌人（不管血量）。
## 屏幕外的敌人不受影响。以后的动画放在这里，节点设成 PROCESS_MODE_ALWAYS，暂停期间照样播放。

## 定格多久（秒）。
@export var freeze_time := 2.0
## 恢复行动后玩家还额外无敌多久（秒），免得屏幕外的敌人刚好打过来。
@export var grace_time := 0.5

## 敌人子弹所在的组（enemy_bullet.tscn 里设置）。
const ENEMY_BULLETS := &"enemy_bullets"


## 武器槽发射时调用；终极武器没有方向。
func launch(_direction: Vector2) -> void:
	pass


func _ready() -> void:
	# 整棵树都会被暂停，这个节点自己得继续跑，才能在时间到了之后恢复。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_activate()


func _activate() -> void:
	var tree := get_tree()
	var targets := enemies_on_screen()
	for bullet in tree.get_nodes_in_group(ENEMY_BULLETS):
		bullet.queue_free()
	var player := tree.get_first_node_in_group("player") as Player
	if player != null:
		# 玩家自己的计时在暂停时也停着，所以这段无敌覆盖整个定格，恢复后再持续 grace_time。
		player.grant_invincibility(grace_time)
	tree.paused = true
	await tree.create_timer(freeze_time, true).timeout
	tree.paused = false
	GameEvents.report(&"ultimate_blast", self)
	for enemy in targets:
		if is_instance_valid(enemy) and enemy.health > 0:
			enemy.die()
	queue_free()


## 此刻身体中心在屏幕可见范围内的敌人。
func enemies_on_screen() -> Array[Enemy]:
	var viewport := get_viewport()
	var visible := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	var found: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy != null and enemy.health > 0 and visible.has_point(enemy.global_position):
			found.append(enemy)
	return found
