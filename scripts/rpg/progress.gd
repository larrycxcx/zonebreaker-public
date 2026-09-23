extends Node
## 所有玩家的成长进度（autoload 单例 Progress）：每人一份 `PlayerProgress`，外加存档和杀敌奖励的分配。
##
## 一份进度里有什么、属性怎么算，都在 `PlayerProgress` 里；这里只管三件事：
## 谁是第几号（`of(index)`）、存档（一个 JSON 文件里放两份）、杀敌奖励发给谁。
##
## 存档写在 `save_path`，任何一份进度有变化就存；测试里 `persist = false`，既不读也不写玩家的真实存档。
## **能读老存档**：双人之前的存档是一份进度直接摊在最外层，读到那种格式就当成 1 号的。
##
## 杀敌奖励：听 GameEvents 的 `enemy_death`，按那个敌人场景里配的 `xp_reward` / `money_reward` 发给
## **打死它的那个玩家**（敌人身上的 `killed_by`）；不知道是谁打死的（比如踩死、以后的陷阱）就算 1 号的。

const BALANCE := "res://progression/balance.tres"
const DEFAULT_SAVE := "user://save.json"

## 是否读写存档。测试关掉它。
var persist := true
var save_path := DEFAULT_SAVE
var balance: Balance

## 每个玩家一份，下标就是 `Player.player_index`。一开始就建满，不等玩家出生。
var profiles: Array[PlayerProgress] = []


func _ready() -> void:
	balance = load(BALANCE) as Balance
	for i in Session.MAX_PLAYERS:
		var profile := PlayerProgress.new(balance)
		profile.changed.connect(save_game)
		profiles.append(profile)
	if persist:
		load_game()
	GameEvents.event_happened.connect(_on_event)


## 第几号玩家的那一份（越界按 1 号算，免得哪里少传一个下标就崩）。
func of(index: int) -> PlayerProgress:
	return profiles[clampi(index, 0, profiles.size() - 1)]


## 所有人都从头开始。不动存档文件（下一次变化时才会覆盖）。
func new_game() -> void:
	for profile in profiles:
		profile.new_game()


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	if not persist:
		return
	var data := {"players": profiles.map(func(p: PlayerProgress) -> Dictionary: return p.to_dict())}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


## 读存档；没有存档或读坏了就保持新开一局的样子。
func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_warning("Progress: 存档读不出来，按新开一局处理：%s" % save_path)
		return
	# 双人之前的存档是一份进度直接摊在最外层，没有 players 这一项
	var saved: Array = (data as Dictionary).get("players", [data])
	for i in mini(saved.size(), profiles.size()):
		if saved[i] is Dictionary:
			profiles[i].from_dict(saved[i])


func _on_event(event: StringName, source: Node) -> void:
	if event != &"enemy_death" or source == null:
		return
	var killer: Variant = source.get(&"killed_by")
	var who := of(killer.player_index if killer is Player else 0)
	who.add_money(int(source.get(&"money_reward")) if source.get(&"money_reward") != null else 0)
	who.add_xp(int(source.get(&"xp_reward")) if source.get(&"xp_reward") != null else 0)
