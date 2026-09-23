extends Node2D
## 关卡根节点：玩家死亡后重开本关。

@export var respawn_delay := 1.2
## 玩家死亡后隔多久报告 game_over（让死亡音效先响一会儿）。
## 声音由 Sfx 单例播放，关卡重载不会把它截断。
@export var game_over_delay := 0.5

## 2 号玩家出生在 1 号旁边多远。
@export var second_player_offset := Vector2(-28, 0)

@onready var _player: Player = $Player


func _ready() -> void:
	_add_players()
	_add_huds()
	_add_backdrop()
	# 关卡里的音乐；死了重开时已经在放同一首就接着放，不会从头来（见 Music）
	Music.play(&"level")
	_player.died.connect(_on_player_died)


## 双人时在 1 号旁边放一个 2 号：同一个玩家场景，`player_index` = 1（读 p2_ 那套输入、用自己那份进度）。
func _add_players() -> void:
	if Session.player_count < 2:
		return
	var second := (load(_player.scene_file_path) as PackedScene).instantiate() as Player
	second.name = "Player2"
	second.player_index = 1
	add_child(second)
	move_child(second, _player.get_index() + 1)
	second.global_position = _player.global_position + second_player_offset


## 双人时给 2 号也来一套 HUD，摆在屏幕右边。Boss 血条和死亡提示是两个人共用的，只由左边那套显示，
## 否则两套会叠在一起（`shows_shared`）。
func _add_huds() -> void:
	if Session.player_count < 2:
		return
	var hud := $HUD as CanvasLayer
	var second := (load(hud.scene_file_path) as PackedScene).instantiate()
	second.name = "HUD2"
	second.player_index = 1
	second.mirrored = true
	second.shows_shared = false
	add_child(second)


## 当前素材包有背景就放到最底下（第一个子节点最先画）。纯显示，没有就用项目的清屏色。
func _add_backdrop() -> void:
	var scene := Skins.backdrop()
	if scene == null:
		return
	var backdrop := scene.instantiate()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	move_child(backdrop, 0)


func _on_player_died() -> void:
	await get_tree().create_timer(game_over_delay).timeout
	GameEvents.report(&"game_over", self)
	await get_tree().create_timer(respawn_delay - game_over_delay).timeout
	# 在测试里场景是手动实例化的，没有 current_scene，此时不重载。
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()
