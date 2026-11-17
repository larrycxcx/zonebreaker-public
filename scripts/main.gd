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
## 纵向关里掉出画面底边多远才算掉出去：和横向关一样留 40（地面 320、画面底 360、判定线 400）。
const FALL_MARGIN := 40.0
## 敌人被甩在画面底边以下多远就收走（比玩家的判定线再低一截：刚出画面的还可能被打到）。
const LEFT_BEHIND := 120.0
## Boss 倒下之后隔多久摆成绩单：让爆炸和屏幕抖动走完。
@export var clear_delay := 1.5

@onready var _player: Player = $Player
## 全灭之后让玩家选「再来一次 / 回主菜单」的那一层。关卡里没有就照老样子自动重开。
@onready var _death: DeathScreen = get_node_or_null("DeathScreen")
## 打完之后摆成绩单的那一层。关卡里没有就只好什么都不做（打完站在原地）。
@onready var _clear: ClearScreen = get_node_or_null("ClearScreen")
## 这一关已经结束了（全灭或者打完）。双人时两个人可能同一帧死，没这个会报两次 game_over；
## 也免得 Boss 倒下的同一刻最后一个玩家也死了，两页一起弹出来。
var _over := false
## 进关卡那一刻每个座位的经验、金钱、等级——结算页要拿它们算「这一关赚了多少」。
var _started: Array[Dictionary] = []


## 格子地图生成的关卡，画面交给砖（`FrontTiles`），碰撞的平台都藏着。**砖的素材不在**
## （公开版去掉了第三方素材）时什么都画不出来、地面是透明的，所以把那些平台露出来，
## 用平台自己的占位外观（纯色方块）当地形——规则一点没变，只是退回方块的样子。
func _show_bare_terrain() -> void:
	var tiles := get_node_or_null("FrontTiles") as TileArt
	if tiles == null or tiles.atlas != null:
		return
	# 只露 `Level` 底下的平台：梯子顶那块看不见的盖子（挂在梯子下面）本来就不该画
	for node in get_node("Level").get_children():
		if node is Platform:
			(node as Platform).visible = true


func _ready() -> void:
	_add_players()
	_add_huds()
	_add_backdrop()
	_add_lighting()
	_show_bare_terrain()
	# 关卡里的音乐；死了重开时已经在放同一首就接着放，不会从头来（见 Music）
	Music.play(&"level")
	for node in get_tree().get_nodes_in_group(&"player"):
		(node as Player).died.connect(_on_player_died)
	_remember_start()
	# Boss 可能是关卡中途生出来的，所以走总线等它出场，再接它的死讯
	GameEvents.boss_appeared.connect(_on_boss_appeared)


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


## 当前素材包有光照层就插在**地形后面、敌人前面**：背景、装饰、地形被它染色，
## 人和子弹画在它上面、保持原色（见 `ScreenLight`）。没有 `Level` 的话就放在背景后面。
func _add_lighting() -> void:
	var scene := Skins.lighting()
	if scene == null:
		return
	var light := scene.instantiate()
	light.name = "Lighting"
	var level := get_node_or_null("Level")
	add_child(light)
	move_child(light, level.get_index() + 1 if level != null else 1)


## 谁都不剩了才算输（HUD 也要问同一件事，所以判断在 `Player` 上）。
func _anyone_left() -> bool:
	return Player.anyone_left(get_tree())


## 关卡里才算游戏时长：菜单和暂停不算（暂停时整棵树停了，这里本来就不跑）。
func _process(delta: float) -> void:
	Progress.tick_playtime(delta)


## 掉进坑里的收干净。玩家扣血捞回最后站稳的地方（`Player.fall_out()`）；敌人照常 `die()`——
## 把追着你的 D 引到坑边推下去，经验照给（没人打过的算 1 号的，见 `Progress`）。
func _physics_process(_delta: float) -> void:
	var line := player_fall_line()
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		# 倒地的也要捞：他已经没血可扣，但扔在坑底下队友永远够不着
		if player != null and (player.is_alive() or player.is_downed()) 				and player.global_position.y > line:
			player.fall_out()
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		# 已经排队等删的别再 die 一次，不然 enemy_death 会报两遍、奖励也发两份
		if enemy.global_position.y > fall_y:
			enemy.die()
		elif enemy.global_position.y > line + LEFT_BEHIND:
			# 纵向关里画面卷走、被甩在底下的：**悄悄删掉**，不给经验也不报死——
			# 玩家没打它，而且留着的话它会在画面外往上打冷枪
			enemy.queue_free()


## 玩家掉到哪条线以下算掉出去。横向关就是固定的 `fall_y`；
## 纵向关（摄像机 `only_up`）跟着画面底边走：画面卷上去以后，掉出底边就回不来了。
func player_fall_line() -> float:
	var rig := CameraRig.find(get_tree())
	if rig == null or not rig.only_up:
		return fall_y
	return minf(fall_y, rig.view_rect().end.y + FALL_MARGIN)


## 进关卡那一刻先把每个座位的经验、金钱、等级记下来，结算页拿它们算差值。
func _remember_start() -> void:
	_started.clear()
	for index in Session.player_count:
		var who := Progress.of(index)
		_started.append({"xp": who.xp, "money": who.money, "level": who.level})


func _on_boss_appeared(boss: Node2D) -> void:
	var it := boss as Boss
	if it != null and not it.died.is_connected(_on_boss_died):
		it.died.connect(_on_boss_died)


## Boss 倒下 = 这一关打完了。以前打死 Boss 什么都不会发生，
## 关卡只有一个出口——全灭；23 关要接得上，就得有「打完了」这件事。
func _on_boss_died() -> void:
	if _over:
		return
	_over = true
	GameEvents.report(&"level_clear", self)
	_unlock_next()
	await get_tree().create_timer(clear_delay).timeout
	if _clear != null:
		_clear.open(_results(), Catalog.index_of(Stage.current) + 1 < Catalog.count())


## 把进度往前推一关。**双人取两个人里最高的**，然后两个人都设成它——
## 老手带新人时，朋友的新角色也跟着解锁，不用卡着重打十几关。
func _unlock_next() -> void:
	var at := Catalog.index_of(Stage.current)
	if at < 0:
		return                                    # 测试关不在清单里，没有进度可推
	var unlocked := at + 2                        # 关卡从 0 数，解锁数从 1 数
	for index in Session.player_count:
		unlocked = maxi(unlocked, Progress.of(index).reached)
	# **只往上推，不往下夹**：卸载了关卡 DLC 之后存档里的进度不该被抹掉
	#（真要用的时候 `MainMenu._unlocked()` 会按现有关卡数切一刀）
	for index in Session.player_count:
		var who := Progress.of(index)
		who.reached = maxi(who.reached, unlocked)
	Progress.save_game()


## 每个座位这一关赚了多少（结算页照着摆，双人两栏）。
func _results() -> Array:
	var out := []
	for index in Session.player_count:
		var who := Progress.of(index)
		var before: Dictionary = _started[index] if index < _started.size() else {}
		var gained := who.level - int(before.get("level", who.level))
		# 升了级的话经验会清零重算，差值就不对了——按「升了几级」把跨过的那几档补回来
		var xp: int = who.xp - int(before.get("xp", 0))
		for step in gained:
			xp += who.balance.xp_to_next(int(before.get("level", 1)) + step)
		out.append({
			"name": who.character_name, "level": who.level, "levels_gained": gained,
			"xp": maxi(0, xp), "money": maxi(0, who.money - int(before.get("money", 0))),
		})
	return out


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
