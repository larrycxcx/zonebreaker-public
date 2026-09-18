extends Node2D
## 关卡根节点：玩家死亡后重开本关。

@export var respawn_delay := 1.2

@onready var _player: Player = $Player


func _ready() -> void:
	_player.died.connect(_on_player_died)


func _on_player_died() -> void:
	await get_tree().create_timer(respawn_delay).timeout
	# 在测试里场景是手动实例化的，没有 current_scene，此时不重载。
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()
