class_name PlayerProgress
extends RefCounted
## One character's progression: name, look, level, XP, money, skill points and how they are spent, gear in the bag, gear equipped.
##
## **The identity is the character, not the seat**: the save holds a roster of characters, and at the start each player picks one from it (or creates one) to sit in.
## The roster and the seats both belong to the autoload `Progress`, which also handles saving and who gets each kill reward.
## **It lives outside the stage**: when a player dies and the stage restarts, the whole stage including the player node is rebuilt, so none of this can be stored on the player —
## everything is kept after death (by design; grinding is allowed). A player reads its stats and weapons from its own progress on spawn, and again whenever the stats change (`stats_changed`).
##
## Stat = starting value (Balance.base) + points × per-point gain + the bonuses of all equipped gear, capped by Balance.cap.

## Stats changed (points spent, gear changed, level up). The player recomputes max health, damage, cooldowns and sprint length from it.
signal stats_changed
## Any of XP, money, level or skill points changed (for the HUD).
signal progress_changed
signal leveled_up(level: int)
## Anything changed; `Progress` listens and saves.
signal changed

## Weapons carried when starting a new game.
const STARTING_GEAR: Array[String] = ["res://weapons/rifle.tres", "res://weapons/grenade.tres"]
## Which look to use when none was picked.
const DEFAULT_LOOK := &"biker"
## Maximum name length. The name field in the UI and the save list are laid out for this width.
const NAME_LIMIT := 10


## Tidy up a typed name into something that can be saved: upper case, letters, digits and spaces only, trimmed at both ends, length limited.
## The UI is always English upper case (the pack's font only has these, see CLAUDE.md).
static func sanitize_name(raw: String) -> String:
	var kept := ""
	for ch in raw.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ":
			kept += ch
	return kept.strip_edges().substr(0, NAME_LIMIT)

var balance: Balance

## Character name (upper-case letters, digits and spaces, see `sanitize_name()`). No duplicate names in the roster.
var character_name := ""
## Which look to use (skin key). Purely cosmetic, can change any time, affects no rule.
var look := DEFAULT_LOOK
## How long this character has been played (seconds). Only counted in stages; menus and pause do not count.
var played_seconds := 0.0
## When it was last saved (`Time.get_datetime_string_from_system()`), shown in the save list.
var saved_at := ""

var level := 1
## **How far this character has got**: how many stages are unlocked (1 = only the first).
## **Stored on the character**, not globally — each character is its own playthrough, and a new one starts at stage 1, consistent with the roster design.
var reached := 1
var xp := 0
var money := 0
## Skill points not spent yet.
var points := 0
## Points spent on each stat.
var allocated: Dictionary[StringName, int] = {}
## Gear owned (including what is equipped).
var owned: Array[Equipment] = []
## Gear equipped: slot → item.
var equipped: Dictionary[int, Equipment] = {}


func _init(from_balance: Balance) -> void:
	balance = from_balance
	new_game()


## Start from scratch: level 1, no money, only the starting weapons, plus a few skill points to spend right away (`Balance.starting_points`).
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


# ---------------------------------------------------------------- Stats

## The current value of a stat.
func stat(name: StringName) -> float:
	var value: float = balance.base.get(name, 0.0) + allocated.get(name, 0) * balance.per_point.get(name, 0.0)
	for item: Equipment in equipped.values():
		value += item.bonuses.get(name, 0.0)
	if balance.cap.has(name):
		value = minf(value, balance.cap[name])
	return value


## Resistance to a status (0..1): the highest among the equipped gear.
func resistance(status: StringName) -> float:
	var best := 0.0
	for item: Equipment in equipped.values():
		best = maxf(best, item.resist.get(status, 0.0))
	return clampf(best, 0.0, 1.0)


## The item equipped in a slot, null if none.
func gear(slot: Equipment.Slot) -> Equipment:
	return equipped.get(slot)


# ---------------------------------------------------------------- XP, level, skill points, money

## At max level? At max level XP no longer accumulates (`xp_to_next` returns 0, the UI shows MAX).
## Play time starts counting as soon as a stage loads (`main.gd` calls `tick_playtime()` every frame), so "never played" cannot mean exactly 0 —
## the few frames after sitting down add a little too. Allow one second of grace: anyone who really played, even for a few seconds, is kept;
## only "sat down and got straight back up" counts as never played.
const UNPLAYED_GRACE := 1.0


## Has this character **never been played for a minute and never been changed at all**? Choosing NEW in the menu creates a character on the spot,
## and when going back to choose again this decides whether the previous one stays in the roster (see `Progress.take_seat()`).
## Name and look do not count — renaming or changing the face without deciding to play should not take up a row in the save list.
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


## Take back one point spent on a stat. Not possible if the stat has no points in it; returns whether a point was taken back.
## **Only your own points can be taken back**: the starting value is the floor, you cannot go below it.
func unspend_point(name: StringName) -> bool:
	if allocated.get(name, 0) <= 0:
		return false
	allocated[name] -= 1
	if allocated[name] == 0:
		allocated.erase(name)
	points += 1
	_changed(true)
	return true


## Has this stat hit its cap (points + gear together reaching `Balance.cap`)?
func is_capped(name: StringName) -> bool:
	return balance.cap.has(name) and stat(name) >= balance.cap[name]


## Spend a skill point on a stat. Nothing happens without points, with a wrong stat name, **or when the stat is already capped**; returns whether it was spent.
## Accepting points at the cap would take the point and increase `allocated` while `stat()` stays clamped at the cap — the player could not tell they were throwing points away.
func spend_point(name: StringName) -> bool:
	if points <= 0 or not Balance.STATS.has(name) or is_capped(name):
		return false
	points -= 1
	allocated[name] = allocated.get(name, 0) + 1
	_changed(true)
	return true


# ---------------------------------------------------------------- Shop, gear

## Buy an item: if there is enough money, pay and put it in the bag; returns whether it was bought. Items already owned are not bought again.
func buy(item: Equipment) -> bool:
	if item == null or owned.has(item) or money < item.price:
		return false
	money -= item.price
	owned.append(item)
	_changed(false)
	return true


## Take off the item in a slot (it stays in the bag). Does nothing if the slot is already empty.
func unequip(slot: Equipment.Slot) -> bool:
	if not equipped.has(slot):
		return false
	equipped.erase(slot)
	_changed(true)
	return true


## Can this item be used yet (level requirement)? **You can buy it before you can wear it**: with money to spare, stock up first and wear it once you have the level —
## without the requirement, enough grinding for money would let you wear top gear early and the curve over 23 stages would collapse right there.
func can_equip(item: Equipment) -> bool:
	return item != null and item.min_level <= level


## Equip an item from the bag (whatever was in that slot stays in the bag). Not possible without the level.
func equip(item: Equipment) -> bool:
	if item == null or not owned.has(item) or not can_equip(item):
		return false
	equipped[item.slot] = item
	_changed(true)
	return true


## Selling price: **half the original price**. The game does not drop gear, so selling cannot become a money exploit.
static func sell_price(item: Equipment) -> int:
	return 0 if item == null else item.price / 2


## Can it be sold? **Free items cannot be sold** (the starting rifle and grenade have no price; the same line as `Catalog.gear_for_sale()`):
## they would sell for 0, and allowing it would let the player swap their only gun for nothing — a pure trap.
static func can_sell(item: Equipment) -> bool:
	return item != null and item.price > 0


## Sell an item (**equipped items can be sold too**, they are taken off automatically). Returns the money received, 0 if nothing was sold.
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


## What the four stats would become after putting this on (`wear`) or taking it off (not wear).
## The shop's "now → after" line comes from this; **the gear is put back afterwards**, nothing is really changed.
## A weapon's real numbers **in this character's hands**: damage per shot, shots per second, ammo cap (-1 = unlimited).
## The shop and character setup both read this — attack and speed are included, so the same gun shows different numbers for different characters.
##
## Damage is worked out exactly as the weapon slot does when really firing (`WeaponSlot.fire()` → `scale_damage(power × attack multiplier)`);
## if the two drifted apart, the UI would show a misleading number.
## Bullets use `damage`, grenades `max_damage` (the centre hit), so both kinds show **the most a single hit can do**.
func weapon_numbers(weapon: Weapon) -> Dictionary:
	if weapon == null:
		return {}
	var out := {
		&"rate": 1.0 / maxf(0.01, weapon.cooldown * Balance.cooldown_scale(stat(Balance.SPEED))),
	}
	# **Unlimited ammo is not listed**: `max_ammo` is -1, and copied as is the UI would show a line saying `AMMO -1`.
	# The rifle and grenade are both unlimited, so this line only appears for limited ammo like the ultimate.
	if weapon.max_ammo >= 0:
		out[&"ammo"] = float(weapon.max_ammo)
	var damage := _projectile_damage(weapon)
	if damage > 0:
		out[&"damage"] = maxf(1.0, roundf(damage * weapon.power * Balance.damage_scale(stat(Balance.ATTACK))))
	return out


## How much the projectile itself deals. **`instantiate()` does not run `_ready`** (that only happens once added to the tree),
## so creating one here, reading it and throwing it away is safe: it joins no groups and does not ask the skin pack for a look.
func _projectile_damage(weapon: Weapon) -> float:
	if weapon.projectile == null:
		return 0.0
	var shot := weapon.projectile.instantiate()
	var damage := 0.0
	if shot.get(&"damage") != null:
		damage = float(shot.get(&"damage"))
	elif shot.get(&"max_damage") != null:
		damage = float(shot.get(&"max_damage"))
	shot.free()
	return damage


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


# ---------------------------------------------------------------- Save data (`Progress` reads and writes the file)

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
	# Old saves do not have this; read in, it means "only the first stage unlocked"
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
