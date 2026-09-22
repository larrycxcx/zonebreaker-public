extends Node
## 玩家的成长进度（autoload 单例 Progress）：等级、经验、金钱、技能点和加点、背包里的装备、身上的装备。
##
## **放在关卡外面**：玩家死了重开关卡时整个关卡连同玩家节点都会重建，这些东西不能记在玩家身上——
## 死亡后全部保留（设计如此，允许刷）。玩家出生时从这里读属性和武器，属性一变就重新读（`stats_changed`）。
## 存档写在 `save_path`（JSON），每次有变化就存；测试里 `persist = false`，既不读也不写玩家的真实存档。
##
## 属性 = 初始值（Balance.base）+ 加点 × 每点加多少 + 身上所有装备的加成，再按 Balance.cap 封顶。
## 杀敌奖励：听 GameEvents 的 `enemy_death`，按那个敌人场景里配的 `xp_reward` / `money_reward` 发。

## 属性（加点、换装备、升级）变了。玩家据此重新计算血量上限、伤害、冷却、冲刺时长。
signal stats_changed
## 经验、金钱、等级、技能点任何一个变了（HUD 显示用）。
signal progress_changed
signal leveled_up(level: int)

const BALANCE := "res://progression/balance.tres"
const DEFAULT_SAVE := "user://save.json"
## 新开一局时身上的武器。
const STARTING_GEAR: Array[String] = ["res://weapons/rifle.tres", "res://weapons/grenade.tres"]

## 是否读写存档。测试关掉它。
var persist := true
var save_path := DEFAULT_SAVE
var balance: Balance

var level := 1
var xp := 0
var money := 0
## 还没分配的技能点。
var points := 0
## 每个属性加了几点。
var allocated: Dictionary[StringName, int] = {}
## 拥有的装备（含身上穿着的）。
var owned: Array[Equipment] = []
## 身上的装备：位置 → 装备。
var equipped: Dictionary[int, Equipment] = {}


func _ready() -> void:
	balance = load(BALANCE) as Balance
	new_game()
	if persist:
		load_game()
	GameEvents.event_happened.connect(_on_event)


## 从头开始：1 级、没钱、只有初始武器。不动存档文件（下一次变化时才会覆盖）。
func new_game() -> void:
	level = 1
	xp = 0
	money = 0
	points = 0
	allocated.clear()
	owned.clear()
	equipped.clear()
	for path in STARTING_GEAR:
		var item := load(path) as Equipment
		owned.append(item)
		equipped[item.slot] = item
	stats_changed.emit()
	progress_changed.emit()


# ---------------------------------------------------------------- 属性

## 某个属性现在是多少。
func stat(name: StringName) -> float:
	var value: float = balance.base.get(name, 0.0) + allocated.get(name, 0) * balance.per_point.get(name, 0.0)
	for item: Equipment in equipped.values():
		value += item.bonuses.get(name, 0.0)
	if balance.cap.has(name):
		value = minf(value, balance.cap[name])
	return value


## 对某个异常状态的抗性（0..1）：身上装备里最大的那个。
func resistance(status: StringName) -> float:
	var best := 0.0
	for item: Equipment in equipped.values():
		best = maxf(best, item.resist.get(status, 0.0))
	return clampf(best, 0.0, 1.0)


## 身上某个位置的装备，没有返回 null。
func gear(slot: Equipment.Slot) -> Equipment:
	return equipped.get(slot)


# ---------------------------------------------------------------- 经验、等级、技能点、金钱

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var gained := false
	while xp >= balance.xp_to_next(level):
		xp -= balance.xp_to_next(level)
		level += 1
		points += balance.points_per_level
		gained = true
		leveled_up.emit(level)
	_changed(gained)


func add_money(amount: int) -> void:
	if amount == 0:
		return
	money = maxi(0, money + amount)
	_changed(false)


## 把一个技能点加到某个属性上。没点数或属性名不对就不加，返回是否加上了。
func spend_point(name: StringName) -> bool:
	if points <= 0 or not Balance.STATS.has(name):
		return false
	points -= 1
	allocated[name] = allocated.get(name, 0) + 1
	_changed(true)
	return true


# ---------------------------------------------------------------- 商店、装备

## 买一件装备：钱够就扣钱放进背包，返回是否买成。已经有了的不重复买。
func buy(item: Equipment) -> bool:
	if item == null or owned.has(item) or money < item.price:
		return false
	money -= item.price
	owned.append(item)
	_changed(false)
	return true


## 穿上背包里的一件装备（同一位置原来那件留在背包里）。
func equip(item: Equipment) -> bool:
	if item == null or not owned.has(item):
		return false
	equipped[item.slot] = item
	_changed(true)
	return true


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	if not persist:
		return
	var data := {
		"level": level, "xp": xp, "money": money, "points": points,
		"allocated": allocated,
		"owned": owned.map(func(item: Equipment) -> String: return item.resource_path),
		"equipped": equipped.values().map(func(item: Equipment) -> String: return item.resource_path),
	}
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
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	money = int(data.get("money", 0))
	points = int(data.get("points", 0))
	allocated.clear()
	for name: String in data.get("allocated", {}):
		allocated[StringName(name)] = int(data["allocated"][name])
	var items := {}
	for path: String in data.get("owned", []):
		var item := load(path) as Equipment if ResourceLoader.exists(path) else null
		if item != null:
			items[path] = item
	if not items.is_empty():
		owned.assign(items.values())
		equipped.clear()
		for path: String in data.get("equipped", []):
			if items.has(path):
				equipped[(items[path] as Equipment).slot] = items[path]
	stats_changed.emit()
	progress_changed.emit()


func _changed(stats: bool) -> void:
	if stats:
		stats_changed.emit()
	progress_changed.emit()
	save_game()


func _on_event(event: StringName, source: Node) -> void:
	if event != &"enemy_death" or source == null:
		return
	add_money(int(source.get(&"money_reward")) if source.get(&"money_reward") != null else 0)
	add_xp(int(source.get(&"xp_reward")) if source.get(&"xp_reward") != null else 0)
