class_name PlayerProgress
extends RefCounted
## 一个角色的成长进度：名字、外观、等级、经验、金钱、技能点和加点、背包里的装备、身上的装备。
##
## **身份是角色，不是座位**：存档里是一份角色名册，开局时每个玩家从名册里挑一个（或新建）坐进去。
## 名册和座位都归 autoload `Progress` 管，它还管存档和杀敌奖励发给谁。
## **放在关卡外面**：玩家死了重开关卡时整个关卡连同玩家节点都会重建，这些东西不能记在玩家身上——
## 死亡后全部保留（设计如此，允许刷）。玩家出生时从自己这一份读属性和武器，属性一变就重新读（`stats_changed`）。
##
## 属性 = 初始值（Balance.base）+ 加点 × 每点加多少 + 身上所有装备的加成，再按 Balance.cap 封顶。

## 属性（加点、换装备、升级）变了。玩家据此重新计算血量上限、伤害、冷却、冲刺时长。
signal stats_changed
## 经验、金钱、等级、技能点任何一个变了（HUD 显示用）。
signal progress_changed
signal leveled_up(level: int)
## 任何一处变了，`Progress` 听着存档。
signal changed

## 新开一局时身上的武器。
const STARTING_GEAR: Array[String] = ["res://weapons/rifle.tres", "res://weapons/grenade.tres"]
## 没挑外观时用哪套。
const DEFAULT_LOOK := &"biker"
## 名字最多几个字符。界面上那一栏和存档列表都是按这个宽度排的。
const NAME_LIMIT := 10


## 把玩家敲进来的名字收拾成能存的样子：大写、只留字母数字和空格、掐掉两头的空格、限长。
## 界面一律英文大写（素材包的字模就只有这些，见 CLAUDE.md）。
static func sanitize_name(raw: String) -> String:
	var kept := ""
	for ch in raw.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ":
			kept += ch
	return kept.strip_edges().substr(0, NAME_LIMIT)

var balance: Balance

## 角色名（全大写字母、数字和空格，见 `sanitize_name()`）。名册里不允许重名。
var character_name := ""
## 用哪套外观（皮肤键）。纯装饰，随时可换，不影响任何规则。
var look := DEFAULT_LOOK
## 玩这个角色玩了多久（秒）。只在关卡里累加，菜单和暂停不算。
var played_seconds := 0.0
## 上次存档的时间（`Time.get_datetime_string_from_system()`），存档列表里显示。
var saved_at := ""

var level := 1
## 这个角色**打到第几关**了：已经解锁几关（1 = 只解锁了第一关）。
## **记在角色身上**，不是全局——每个角色是自己的一周目，新建一个从第 1 关开始，和名册的设计一致。
var reached := 1
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


func _init(from_balance: Balance) -> void:
	balance = from_balance
	new_game()


## 从头开始：1 级、没钱、只有初始武器，外加几个可以马上花的技能点（`Balance.starting_points`）。
func new_game() -> void:
	played_seconds = 0.0
	level = 1
	xp = 0
	money = 0
	points = balance.starting_points
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

## 满级了吗。满级之后经验不再累计（`xp_to_next` 返回 0，界面上显示 MAX）。
## 关卡一加载就开始记时长（`main.gd` 每帧调 `tick_playtime()`），所以「没玩过」不能卡在 0 上——
## 坐进去那几帧也会记上一点。给一秒宽限：真玩过的哪怕只玩了几秒也留着，
## 只有「坐下就又站起来」的才算没玩过。
const UNPLAYED_GRACE := 1.0


## 这个角色**一分钟都没玩过、一点也没加过**吗。菜单里按 NEW 就现开一个角色，
## 退回去重选时靠它判断上一个该不该留在名册里（见 `Progress.take_seat()`）。
## 名字和外观不算——改个名、换张脸还没决定要不要玩，不该因此在存档列表里占一行。
func is_untouched() -> bool:
	return (played_seconds < UNPLAYED_GRACE and allocated.is_empty()
		and level == 1 and xp == 0 and money == 0)


func is_max_level() -> bool:
	return level >= balance.max_level


func add_xp(amount: int) -> void:
	if amount <= 0 or is_max_level():
		return
	xp += amount
	var gained := false
	while not is_max_level() and xp >= balance.xp_to_next(level):
		xp -= balance.xp_to_next(level)
		level += 1
		points += balance.points_per_level
		gained = true
		leveled_up.emit(level)
	if is_max_level():
		xp = 0
	_changed(gained)


func add_money(amount: int) -> void:
	if amount == 0:
		return
	money = maxi(0, money + amount)
	_changed(false)


## 把加在某个属性上的点退回来一个。这个属性一点都没加过就退不了，返回是否退了。
## **只退得回自己加的**：初始值是底，退不到底下去。
func unspend_point(name: StringName) -> bool:
	if allocated.get(name, 0) <= 0:
		return false
	allocated[name] -= 1
	if allocated[name] == 0:
		allocated.erase(name)
	points += 1
	_changed(true)
	return true


## 这个属性已经到顶了吗（加点 + 装备加起来碰到 `Balance.cap`）。
func is_capped(name: StringName) -> bool:
	return balance.cap.has(name) and stat(name) >= balance.cap[name]


## 把一个技能点加到某个属性上。没点数、属性名不对、**或者这个属性已经到顶**都不加，返回是否加上了。
## 到顶了还收的话，点数扣了、`allocated` 加了，`stat()` 却夹在上限不动——玩家看不出自己在白扔点数。
func spend_point(name: StringName) -> bool:
	if points <= 0 or not Balance.STATS.has(name) or is_capped(name):
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


## 脱下某个位置的装备（东西还在背包里）。本来就空着就什么都不做。
func unequip(slot: Equipment.Slot) -> bool:
	if not equipped.has(slot):
		return false
	equipped.erase(slot)
	_changed(true)
	return true


## 这件装备够不够得着（等级门槛）。**买得到但穿不上**：钱多的时候先屯着，练到级再穿——
## 没有这道门槛的话，刷够钱就能提前穿上顶级货，23 关的曲线当场塌掉。
func can_equip(item: Equipment) -> bool:
	return item != null and item.min_level <= level


## 穿上背包里的一件装备（同一位置原来那件留在背包里）。等级不够穿不上。
func equip(item: Equipment) -> bool:
	if item == null or not owned.has(item) or not can_equip(item):
		return false
	equipped[item.slot] = item
	_changed(true)
	return true


## 卖出的价钱：**原价的一半**。游戏里不掉装备，所以卖出不会变成刷钱的漏洞。
static func sell_price(item: Equipment) -> int:
	return 0 if item == null else item.price / 2


## 卖得掉吗。**白给的东西卖不掉**（初始的步枪和手雷没标价，和 `Catalog.gear_for_sale()` 同一条线）：
## 卖价是 0，让它卖得掉的话玩家能把自己唯一一把枪换成零块钱，纯粹是个坑。
static func can_sell(item: Equipment) -> bool:
	return item != null and item.price > 0


## 卖掉一件装备（**身上穿着的也能卖**，会自动脱下来）。返回卖了多少钱，没卖成是 0。
func sell(item: Equipment) -> int:
	if item == null or not owned.has(item) or not can_sell(item):
		return 0
	var paid := sell_price(item)
	if equipped.get(item.slot) == item:
		equipped.erase(item.slot)
	owned.erase(item)
	money += paid
	_changed(true)
	return paid


## 把这件穿上（`wear`）或者脱下（不 wear）之后，四个属性会变成多少。
## 商店里那行「现在 → 之后」就靠它；**算完把身上恢复原样**，不真的换。
func stat_preview(item: Equipment, wear: bool) -> Dictionary:
	if item == null:
		return {}
	var before := equipped.duplicate()
	if wear:
		equipped[item.slot] = item
	elif equipped.get(item.slot) == item:
		equipped.erase(item.slot)
	var out := {}
	for name: StringName in Balance.STATS:
		out[name] = stat(name)
	equipped = before
	return out


# ---------------------------------------------------------------- 存档（`Progress` 负责读写文件）

func to_dict() -> Dictionary:
	return {
		"name": character_name, "look": String(look),
		"played": played_seconds, "saved_at": saved_at,
		"level": level, "xp": xp, "money": money, "points": points, "reached": reached,
		"allocated": allocated,
		"owned": owned.map(func(item: Equipment) -> String: return item.resource_path),
		"equipped": equipped.values().map(func(item: Equipment) -> String: return item.resource_path),
	}


func from_dict(data: Dictionary) -> void:
	character_name = sanitize_name(String(data.get("name", "")))
	look = StringName(data.get("look", DEFAULT_LOOK))
	played_seconds = float(data.get("played", 0.0))
	saved_at = String(data.get("saved_at", ""))
	level = int(data.get("level", 1))
	# 老存档没有这一项，读进来就是「只解锁了第一关」
	reached = maxi(1, int(data.get("reached", 1)))
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
	changed.emit()
