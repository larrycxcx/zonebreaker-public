class_name Catalog
extends RefCounted
## "Which stages / characters / gear the game has" — **found by scanning directories, not named in code**.
##
## This matters for DLC later: a Godot DLC is a `.pck` whose files are
## **overlaid onto `res://`** when loaded. As long as the main program looks for content in directories instead of hard-coding lists,
## dropping in a pack adds a stage, a batch of gear or a character without changing a line of the main program.
##
## Each of the three lists is a directory, one small resource per item:
## - `levels/` → `LevelInfo` (stage scene, name, order)
## - `characters/` → `CharacterLook` (skin key, name, order)
## - `weapons/`, `armor/` → `Equipment` (the gear itself)
##
## Sorting is **not by file name** but by the resource's `order`: by file name it would be biker / cyborg / punk,
## the last two would swap places in character setup, and a DLC character would land in the middle.

const LEVELS := "res://levels"
const CHARACTERS := "res://characters"
## Gear may live in several directories (guns and armour apart); scan them all.
const GEAR := ["res://weapons", "res://armor"]


## All stages, sorted by `order`.
static func levels() -> Array[LevelInfo]:
	var found: Array[LevelInfo] = []
	for item in _scan(LEVELS):
		var level := item as LevelInfo
		if level != null and not level.scene_path.is_empty():
			found.append(level)
	found.sort_custom(func(a: LevelInfo, b: LevelInfo) -> bool: return a.order < b.order)
	return found


## Which position this stage has (counting from 0). **Matched by scene path**, not by object: `Stage.current` may be a different instance.
## Returns -1 if it is not in the list.
static func index_of(level: LevelInfo) -> int:
	if level == null:
		return -1
	var all := levels()
	for i in all.size():
		if all[i].scene_path == level.scene_path:
			return i
	return -1


## Number of stages.
static func count() -> int:
	return levels().size()


## The stage a new game starts on (null if there are no stage resources — that means the pack was built incompletely).
static func first_level() -> LevelInfo:
	var all := levels()
	return all[0] if not all.is_empty() else null


## All selectable characters, sorted by `order`.
static func looks() -> Array[CharacterLook]:
	var found: Array[CharacterLook] = []
	for item in _scan(CHARACTERS):
		var look := item as CharacterLook
		if look != null and not String(look.key).is_empty():
			found.append(look)
	found.sort_custom(func(a: CharacterLook, b: CharacterLook) -> bool: return a.order < b.order)
	return found


## What the shop sells: the scanned gear **that has a price**.
## Unpriced items are not merchandise — the starting rifle and grenades (free) and the ultimate (it does not even have a gear slot,
## and if it slipped into the stock it would become a free "gun") are all kept out by this.
## If `level` is given, only items whose level requirement is ≤ it are listed (the shop stocks by current level); left empty (0), everything is listed.
static func gear_for_sale(level := 0) -> Array[Equipment]:
	var found: Array[Equipment] = []
	for folder in GEAR:
		for item in _scan(folder):
			var piece := item as Equipment
			if piece == null or piece.price <= 0:
				continue
			if level > 0 and piece.min_level > level:
				continue
			found.append(piece)
	found.sort_custom(func(a: Equipment, b: Equipment) -> bool: return a.price < b.price)
	return found


## Scan the resources in one directory. A missing directory counts as empty — a DLC not installed, or a directory not created yet,
## must not crash the game, it just means fewer items.
static func _scan(folder: String) -> Array[Resource]:
	var found: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(folder):
		return found
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for name in names:
		# Once exported, `.tres` becomes `.tres.remap`; accept both
		var clean := name.trim_suffix(".remap")
		if not clean.ends_with(".tres") and not clean.ends_with(".res"):
			continue
		var path := folder.path_join(clean)
		if not ResourceLoader.exists(path):
			continue
		var item := load(path)
		if item != null:
			found.append(item)
	return found
