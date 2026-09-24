extends Node2D
## 关卡根节点：玩家死亡后重开本关。

## 全灭后隔多久弹出「再来一次 / 回主菜单」。**0.5 秒 = 倒地动画的长度**，
## 原来是 1.2 秒，试玩嫌干等；但也不能是 0——那一页会把整棵树定住，
## 人刚中枪就定格，倒地动画一帧都播不出来。
@export var respawn_delay := 0.5
## 全灭后隔多久报告 game_over（**0，当场报**）。声音由 Sfx 单例播放（`PROCESS_MODE_ALWAYS`），
## 弹出那一页也不会把它截断，所以不用为了声音留时间。
@export var game_over_delay := 0.0

## 2 号玩家出生在 1 号旁边多远。
@export var second_player_offset := Vector2(-28, 0)
## 掉到这个高度以下就算掉出关卡（坑底）。地面在 y=320，画面底边 360，
## 再往下 40px 才算数——这样贴着地面跑不会误判，掉进坑里又立刻就死。
@export var fall_y := 400.0

@onready var _player: Player = $Player
## 全灭之后让玩家选「再来一次 / 回主菜单」的那一层。关卡里没有就照老样子自动重开。
@onready var _death: DeathScreen = get_node_or_null("DeathScreen")
## 这一关已经结束了。双人时两个人可能同一帧死，没这个会报两次 game_over。
var _over := false


func _ready() -> void:
	_add_players()
	_add_huds()
	_add_backdrop()
	# 关卡里的音乐；死了重开时已经在放同一首就接着放，不会从头来（见 Music）
	Music.play(&"level")
	for node in get_tree().get_nodes_in_group(&"player"):
		(node as Player).died.connect(_on_player_died)


## 双人时在 1 号旁边放一个 2 号：同一个玩家场景，`player_index` = 1（读 p2_ 那套输入、用自己那份进度）。
func _add_players() -> void:
	if Session.player_count < 2:
		return
	var second := (load(_player.scene_file_path) as PackedScene).instantiate() as Player
	second.name = "Player2"
	second.player_index = 1
	# 长什么样由它那份进度里的 `look` 决定（`Player._ready` 里取），这里不管
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


## 谁都不剩了才算输（HUD 也要问同一件事，所以判断在 `Player` 上）。
func _anyone_left() -> bool:
	return Player.anyone_left(get_tree())


## 关卡里才算游戏时长：菜单和暂停不算（暂停时整棵树停了，这里本来就不跑）。
func _process(delta: float) -> void:
	Progress.tick_playtime(delta)


## 掉进坑里的收干净。玩家扣血捞回最后站稳的地方（`Player.fall_out()`）；敌人照常 `die()`——
## 把追着你的 D 引到坑边推下去，经验照给（没人打过的算 1 号的，见 `Progress`）。
func _physics_process(_delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		# 倒地的也要捞：他已经没血可扣，但扔在坑底下队友永远够不着
		if player != null and (player.is_alive() or player.is_downed()) 				and player.global_position.y > fall_y:
			player.fall_out()
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		# 已经排队等删的别再 die 一次，不然 enemy_death 会报两遍、奖励也发两份
		if enemy != null and not enemy.is_queued_for_deletion() and enemy.global_position.y > fall_y:
			enemy.die()


func _on_player_died() -> void:
	if _over or _anyone_left():
		return
	_over = true
	await get_tree().create_timer(game_over_delay).timeout
	GameEvents.report(&"game_over", self)
	await get_tree().create_timer(respawn_delay - game_over_delay).timeout
	if _death != null:
		_death.open()
		return
	# 在测试里场景是手动实例化的，没有 current_scene，此时不重载。
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()
