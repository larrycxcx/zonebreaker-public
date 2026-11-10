extends Node
## 角色名册和座位（autoload 单例 Progress）：存档里是一份**角色**名册，开局时每个玩家挑一个坐进去。
##
## **身份是角色，不是座位**：同一个角色下次可以换个座位玩，两个座位不能同时用同一个角色。
## 一份进度里有什么、属性怎么算，都在 `PlayerProgress` 里；这里管四件事：
## 名册（新建 / 删除 / 重名检查）、座位（`of(index)` 取第几号玩家现在用的那个角色）、存档、杀敌奖励发给谁。
##
## 存档写在 `save_path`，任何一个角色有变化就存；测试里 `persist = false`，既不读也不写玩家的真实存档。
## **能读老存档**：双人之前是一份进度摊在最外层，双人之后是 `players` 里两份，都会迁移成名册里的角色。
##
## 杀敌奖励：听 GameEvents 的 `enemy_death`，按那个敌人场景里配的 `xp_reward` / `money_reward` 发给
## **打死它的那个玩家**（敌人身上的 `killed_by`）；不知道是谁打死的（比如踩死、以后的陷阱）就算 1 号的。

## 名册变了（新建、删除、改名），存档列表据此刷新。
signal roster_changed
## 某个座位换人了。
signal seat_changed(index: int)

const BALANCE := "res://progression/balance.tres"
const DEFAULT_SAVE := "user://save.json"
## 改名之前的项目名。`user://` 跟着 `application/config/name` 走，2026-11 从 FirstGame 改成 ZONE BREAKER，
## 存档目录也跟着换了——旧目录里有存档、新目录里还没有，就搬过来一次（`_adopt_old_save()`）。
const OLD_NAMES := ["FirstGame"]
## 没名字的角色（老存档迁移过来的、测试里现开的）按座位起个名。
const DEFAULT_NAMES := ["PLAYER 1", "PLAYER 2"]
## 没挑外观时按座位给一套，免得双人时两个人长得一样。
## 新角色默认长什么样：**第几个座位就拿清单里的第几个**（`Catalog.looks()`），
## 这样两个玩家默认不会撞脸。清单是扫 `characters/` 来的，不在这里点名。

## 是否读写存档。测试关掉它。
var persist := true
var save_path := DEFAULT_SAVE
var balance: Balance

## 存档里的全部角色。
var roster: Array[PlayerProgress] = []

## 座位 → 现在坐着的角色，下标就是 `Player.player_index`。**要用的时候才现开**（`of()` 里），
## 所以单人玩不会凭空多出一个没人玩的 2 号角色来占着存档列表。
## **坐着的角色一定在名册里**：有进度的就该被存下来，名册就是「存档里有哪些角色」。
var _seats: Array[PlayerProgress] = []


func _ready() -> void:
	balance = load(BALANCE) as Balance
	new_game()
	if persist:
		load_game()
	GameEvents.event_happened.connect(_on_event)


# ---------------------------------------------------------------- 座位

## 第几号玩家现在用的那个角色（越界按 1 号算，免得哪里少传一个下标就崩）。
func of(index: int) -> PlayerProgress:
	var seat := clampi(index, 0, _seats.size() - 1)
	if _seats[seat] == null:
		_seats[seat] = fresh(seat)
	return _seats[seat]


## 让某个座位用名册里的某个角色。同一个角色不能同时坐两个座位——本来就在别的座位上的话，
## 那个座位换成一个新角色（界面上应该先拦住，这里只是兜底）。
func take_seat(index: int, profile: PlayerProgress) -> void:
	if profile == null or index < 0 or index >= _seats.size():
		return
	for other in _seats.size():
		if other != index and _seats[other] == profile:
			_seats[other] = null
			seat_changed.emit(other)
	# **按了 NEW 又改主意的那个不留在名册里**：菜单里每选一次 NEW 就现开一个角色，
	# 退回去重选会把上一个永远留在存档列表里——玩家一晚上攒了十几个没玩过的空角色。
	# 只丢「一分钟都没玩过、一点也没加过」的那种，认真捏过的照样留着。
	var leaving := _seats[index]
	if leaving != null and leaving != profile and leaving.is_untouched():
		roster.erase(leaving)
		roster_changed.emit()
	_seats[index] = profile
	seat_changed.emit(index)
	save_game()


## 这个角色正坐在哪个座位上，没人用返回 -1。
func seat_of(profile: PlayerProgress) -> int:
	return _seats.find(profile)


# ---------------------------------------------------------------- 名册

## 名字有没有被占用（和 `except` 那个角色自己重名不算）。
func name_taken(character_name: String, except: PlayerProgress = null) -> bool:
	var wanted := PlayerProgress.sanitize_name(character_name)
	for profile in roster:
		if profile != except and profile.character_name == wanted:
			return true
	return false


## 新建一个角色放进名册。名字重了或者空的就不建，返回 null。
func create(character_name: String, look := PlayerProgress.DEFAULT_LOOK) -> PlayerProgress:
	var wanted := PlayerProgress.sanitize_name(character_name)
	if wanted.is_empty() or name_taken(wanted):
		return null
	var profile := _new_profile()
	profile.character_name = wanted
	profile.look = look
	roster.append(profile)
	roster_changed.emit()
	save_game()
	return profile


## 从名册里删掉一个角色。它正坐在某个座位上的话，那个座位换成一个新角色。
func remove(profile: PlayerProgress) -> void:
	if profile == null or not roster.has(profile):
		return
	roster.erase(profile)
	for index in _seats.size():
		if _seats[index] == profile:
			_seats[index] = null
			seat_changed.emit(index)
	roster_changed.emit()
	save_game()


## 名册按上次存档时间从新到旧（存档列表就按这个顺序显示）。
func by_recent() -> Array[PlayerProgress]:
	var sorted := roster.duplicate()
	sorted.sort_custom(func(a: PlayerProgress, b: PlayerProgress) -> bool: return a.saved_at > b.saved_at)
	return sorted


## 全部从头开始：名册清空，每个座位现开一个角色。**不动存档文件**（下一次变化时才会覆盖）。
func new_game() -> void:
	roster.clear()
	_seats.clear()
	_seats.resize(Session.MAX_PLAYERS)


# ---------------------------------------------------------------- 游戏时长

## 关卡里每帧调（`main.gd`）。菜单和暂停不算时长，所以这件事由关卡说了算，不在这里自己跑。
func tick_playtime(delta: float) -> void:
	for profile in _seats:
		if profile != null:
			profile.played_seconds += delta


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	if not persist:
		return
	var now := Time.get_datetime_string_from_system()
	for profile in _seats:
		if profile != null:
			profile.saved_at = now
	# 座位记的是**名册里的第几个**，不是名字：名字是玩家改的，万一重了就认错人
	var data := {
		"characters": roster.map(func(p: PlayerProgress) -> Dictionary: return p.to_dict()),
		"seats": _seats.map(func(p: PlayerProgress) -> int: return roster.find(p) if p != null else -1),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


## 项目改过名的话，把旧名字那个目录里的存档拷过来（只拷一次：新目录里有了就不动）。
## 拷而不是挪：万一新版本出了问题，退回老版本存档还在原处。
## `target` 是新存档的完整路径，`parent` 是各个项目数据目录所在的那一层（测试传临时目录）。
## 拷过来了返回 true。
func adopt_old_save(target: String, parent: String) -> bool:
	if FileAccess.file_exists(target):
		return false
	for old_name: String in OLD_NAMES:
		var old := parent.path_join(old_name).path_join("save.json")
		if FileAccess.file_exists(old):
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			return DirAccess.copy_absolute(old, target) == OK
	return false


## 读存档；没有存档或读坏了就保持新开一局的样子。
func load_game() -> void:
	if save_path == DEFAULT_SAVE:
		adopt_old_save(ProjectSettings.globalize_path(DEFAULT_SAVE), OS.get_user_data_dir().get_base_dir())
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_warning("Progress: 存档读不出来，按新开一局处理：%s" % save_path)
		return
	var saved: Array = _characters_in(data as Dictionary)
	if saved.is_empty():
		return
	roster.clear()
	for entry in saved:
		if not entry is Dictionary:
			continue
		var profile := _new_profile()
		profile.from_dict(entry)
		# 名字空的给一个，**重了的也当场改掉**：老存档里可能已经攒着一堆同名的
		# （见 `_free_name` 那段），留着的话列表上全是一模一样的行、座位也认错人。
		if profile.character_name.is_empty():
			profile.character_name = _free_name(DEFAULT_NAMES[mini(roster.size(), DEFAULT_NAMES.size() - 1)])
		elif name_taken(profile.character_name):
			profile.character_name = _free_name(profile.character_name)
		roster.append(profile)
	# 座位：找回上次坐着的那个，找不到就按顺序拿名册里的；名册里也没有就留空，
	# 等真有玩家来坐（`of()`）再现开，免得单人玩也在名册里留一个没人玩的 2 号。
	var wanted: Array = (data as Dictionary).get("seats", [])
	for index in _seats.size():
		var seated := _seated(wanted[index]) if index < wanted.size() else null
		if seated == null and index < roster.size():
			seated = roster[index]
		_seats[index] = seated
	roster_changed.emit()


## 存档里的角色列表。老格式一起认：
## `{"players": [a, b]}` 是双人之前那版（一个座位一份），更早的是一份进度直接摊在最外层。
func _characters_in(data: Dictionary) -> Array:
	if data.has("characters"):
		return data["characters"]
	if data.has("players"):
		return data["players"]
	return [data] if data.has("level") else []


## 存档里记的那个座位坐着谁。新格式是名册下标，**老存档记的是名字**，两种都认。
func _seated(mark: Variant) -> PlayerProgress:
	if mark is float or mark is int:
		var at := int(mark)
		return roster[at] if at >= 0 and at < roster.size() else null
	return _find(String(mark))


func _find(character_name: String) -> PlayerProgress:
	for profile in roster:
		if profile.character_name == character_name:
			return profile
	return null


## 现开一个角色并放进名册：座位上坐着的一定是名册里的人，不然他的进度存不下来。
## 名字先按座位取一个（重了就加数字），玩家可以在设置界面里改。
## 菜单里选 NEW 就是调它，再 `take_seat()` 坐进去。
func fresh(index: int) -> PlayerProgress:
	var profile := _new_profile()
	profile.character_name = _free_name(DEFAULT_NAMES[mini(index, DEFAULT_NAMES.size() - 1)])
	var looks := Catalog.looks()
	if not looks.is_empty():
		profile.look = looks[mini(index, looks.size() - 1)].key
	roster.append(profile)
	return profile


func _new_profile() -> PlayerProgress:
	var profile := PlayerProgress.new(balance)
	profile.changed.connect(save_game)
	return profile


## 没被占用的名字：先用想要的那个，重了就在后面加数字。
##
## **加数字之前先给数字腾地方**：名字最多 `NAME_LIMIT`(10) 个字符，直接拼再截的话
## `PLAYER 1` + ` 10` 会截回 `PLAYER 1 1`，从 11 往后每一个都截成同一串、全被占着，
## 数完就把重复的那个原样交出去——玩家的存档里于是攒出了六个一模一样的 `PLAYER 1`
## （2026-09 实际踩到，存档列表整页都是同名的行，座位也按名字认错人）。
## 腾了地方之后每个候选的数字尾巴都不一样，所以一定互不相同，
## 名册里有几个人就最多试几次，必定找得到没被占的那个。
func _free_name(wanted: String) -> String:
	if not name_taken(wanted):
		return wanted
	for n in range(2, roster.size() + 3):
		var suffix := " %d" % n
		var base := wanted.substr(0, PlayerProgress.NAME_LIMIT - suffix.length())
		var tried := PlayerProgress.sanitize_name(base + suffix)
		if not name_taken(tried):
			return tried
	return wanted


func _on_event(event: StringName, source: Node) -> void:
	if event != &"enemy_death" or source == null:
		return
	var killer: Variant = source.get(&"killed_by")
	var who := of(killer.player_index if killer is Player else 0)
	# 奖励也按这一关的倍率给：越往后的关卡打一个敌人赚得越多（`Stage`）
	var scale := Stage.reward_scale()
	who.add_money(roundi(int(source.get(&"money_reward")) * scale) if source.get(&"money_reward") != null else 0)
	who.add_xp(roundi(int(source.get(&"xp_reward")) * scale) if source.get(&"xp_reward") != null else 0)
