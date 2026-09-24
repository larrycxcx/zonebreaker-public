class_name Catalog
extends RefCounted
## 「游戏里有哪些关卡 / 角色 / 装备」——**扫目录得来的，不是代码里点名的**。
##
## 这件事关系到以后能不能做 DLC：Godot 的 DLC 是一个 `.pck`，加载时把里面的文件
## **叠加进 `res://`**。所以只要主程序是去目录里找内容、而不是在常量里写死清单，
## 丢一个包进去就能多出一关、一批装备、一个角色，主程序一行都不用改。
##
## 三张清单各是一个目录，每样东西一个小资源：
## - `levels/` → `LevelInfo`（关卡场景、名字、排序）
## - `characters/` → `CharacterLook`（皮肤键、名字、排序）
## - `weapons/`、`armor/` → `Equipment`（装备本身）
##
## 排序**不按文件名**，按资源里的 `order`：按文件名排的话 biker / cyborg / punk，
## 人物设置界面上后两个会对调，加一个 DLC 角色还会插到中间去。

const LEVELS := "res://levels"
const CHARACTERS := "res://characters"
## 装备可能放在好几个目录里（枪、防具分开），都扫。
const GEAR := ["res://weapons", "res://armor"]


## 全部关卡，按 `order` 排好。
static func levels() -> Array[LevelInfo]:
	var found: Array[LevelInfo] = []
	for item in _scan(LEVELS):
		var level := item as LevelInfo
		if level != null and not level.scene_path.is_empty():
			found.append(level)
	found.sort_custom(func(a: LevelInfo, b: LevelInfo) -> bool: return a.order < b.order)
	return found


## 这一关排第几（从 0 数）。**按场景路径认**，不按对象认：`Stage.current` 可能是另一份实例。
## 不在清单里返回 -1。
static func index_of(level: LevelInfo) -> int:
	if level == null:
		return -1
	var all := levels()
	for i in all.size():
		if all[i].scene_path == level.scene_path:
			return i
	return -1


## 一共几关。
static func count() -> int:
	return levels().size()


## 从头开始玩的那一关（没有关卡资源时返回 null——那说明装包装漏了）。
static func first_level() -> LevelInfo:
	var all := levels()
	return all[0] if not all.is_empty() else null


## 全部可选角色，按 `order` 排好。
static func looks() -> Array[CharacterLook]:
	var found: Array[CharacterLook] = []
	for item in _scan(CHARACTERS):
		var look := item as CharacterLook
		if look != null and not String(look.key).is_empty():
			found.append(look)
	found.sort_custom(func(a: CharacterLook, b: CharacterLook) -> bool: return a.order < b.order)
	return found


## 商店里卖的东西：扫到的装备里**标了价的**那些。
## 没标价的不是商品——初始的步枪和手雷（白给）、终极武器（它连装备位都没配，
## 真混进货单里会变成一把白送的「枪」）都因此被挡在外面。
## `level` 给了就只列门槛 ≤ 它的（商店按当前等级上货）；留空（0）列全部。
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


## 扫一个目录下的资源。目录不存在就当空的——DLC 没装、或者哪个目录还没建，
## 不该让游戏崩，只是少几样东西。
static func _scan(folder: String) -> Array[Resource]:
	var found: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(folder):
		return found
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for name in names:
		# 导出成包之后 `.tres` 会变成 `.tres.remap`，两种都要认
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
