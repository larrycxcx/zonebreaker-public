class_name Equipment
extends Resource
## A piece of gear (resource file): which slot it goes in, its price, which stats it boosts, which statuses it resists. Data only.
## Weapons (`Weapon`) are gear too: the gun and the grenade each take a slot, and their kind, look and stats can all differ.
## Pure stat gear later on (armour, trinkets) uses this class directly, no new script needed.

## Slots on the body; one item per slot at a time. **The order is the order of the 8 boxes in character setup**; do not shuffle it.
## The first two are weapons (gun, grenade), the middle five are the five armour pieces, the last one is a trinket.
enum Slot {
	GUN,      ## Gun (automatic / single shot, the player's main weapon)
	GRENADE,  ## Grenade (grenade launcher)
	HEAD,     ## Helmet
	BODY,     ## Breastplate
	LEGS,     ## Trousers
	FEET,     ## Boots
	HANDS,    ## Gloves
	TRINKET,  ## Trinket
}

## What the UI calls each slot (upper case; the UI is always in English, see CLAUDE.md).
const SLOT_NAMES := {
	Slot.GUN: "GUN", Slot.GRENADE: "BOMB", Slot.HEAD: "HEAD", Slot.BODY: "BODY",
	Slot.LEGS: "LEGS", Slot.FEET: "FEET", Slot.HANDS: "HANDS", Slot.TRINKET: "TRINKET",
}

## Name shown in the UI. **English upper case** — the pack's font has no Chinese glyphs and Chinese text turns into a row of boxes (see CLAUDE.md).
@export var display_name := ""
@export var slot := Slot.GUN
## Shop price.
@export var price := 0
## Level needed to buy / use it. The shop only sells items with a requirement ≤ the current level (higher ones are greyed out as a carrot).
## **Without a requirement, enough money would buy gear far too strong**, and the curve over 23 stages would collapse.
@export var min_level := 1
## Stat bonuses: stat name (`Balance.STATS`) → amount added straight to the stat (may be negative: a heavy weapon lowering fire rate and the like).
@export var bonuses: Dictionary[StringName, float] = {}
## Status resistances: status name (`StatusEffect.id`) → 0..1, 1 = fully immune. With several items the highest one counts.
@export var resist: Dictionary[StringName, float] = {}
## Icon shown in the shop, bag and character setup (32×32). Empty draws an empty box.
## **A path, not the texture**: icons live in the skin pack, and if the pack is missing (the public build strips third-party art)
## a direct reference would make the whole `.tres` fail to load and you could not even get your gun; with a path only the icon is blank.
@export_file("*.png") var icon_path := ""
## The icon itself: only loaded if a file exists at the path, otherwise null (the UI draws an empty box). Can also be set directly (for tests).
var icon: Texture2D:
	get:
		if _icon == null and not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			_icon = load(icon_path) as Texture2D
		return _icon
	set(value):
		_icon = value
var _icon: Texture2D
