class_name LevelInfo
extends Resource
## The card of a stage: where its scene is, what it is called, where it sits in the order.
##
## The stage list comes from **scanning the `levels/` directory** (see `Catalog`), so adding a stage = dropping a `.tres` in there
## plus a scene, without changing a line of the main program — DLC goes the same way.
##
## Fields to add later (recommended level, clear reward, which stage is next) go here too; do not scatter them back into code.

## Path of the stage scene. **A path, not a PackedScene**: storing the resource would make this `.tres` drag the whole stage into memory,
## when the menu only wants to know which stages exist.
@export_file("*.tscn") var scene_path := ""
## What the UI calls it (always English upper case; the pack's font has no Chinese glyphs).
@export var display_name := ""
## Position in the order. **Not sorted by file name**: by file name a DLC stage would land in the middle.
@export var order := 0
## Recommended level: coming in below it will be hard. Shown to the player in the UI, never enforced.
@export var recommended_level := 1

## Which skin pack this stage uses: tiles, backdrop, level music, boss music and this stage's enemy sprites are all in it.
## **One pack per stage** — the 23 stages all have different scenes, enemies, bosses and music; sharing one pack would mean sharing one backdrop.
## Packs are chained with `SkinPack.fallback`: whatever `zone_02` leaves out (characters, bullets, effects, HUD, UI)
## is looked up in the common pack, so each stage's pack only holds what is unique to that stage.
## Empty = do not switch; use the one from the project settings (the test level works like this).
## **A path, not the resource**: the packs are third-party art, missing from the public build. A direct reference would make this `.tres` unreadable
## and the stage would vanish from stage select; with a path, `skin` is null when the pack is missing and the stage still plays (with the default placeholder skin).
@export_file("*.tres") var skin_path := ""
## The pack itself: only loaded if the file exists at the path. Can also be set directly (for tests).
var skin: SkinPack:
	get:
		if _skin == null and not skin_path.is_empty() and ResourceLoader.exists(skin_path):
			_skin = load(skin_path) as SkinPack
		return _skin
	set(value):
		_skin = value
var _skin: SkinPack

@export_group("Strength")
## Multipliers for this stage's enemy health / damage / rewards. **All 23 stages use the same enemies** and these three numbers set the difficulty,
## instead of a new set of enemy scenes per stage (see `Stage`).
## **For the real stages these are all 1.0 by default**: every stage has its own enemies anyway, with health and damage written into each enemy scene.
## These three numbers are for **difficulty DLC** — same stage, same art, same enemies, just higher multipliers,
## so players replay with their existing characters (Hard, Hell). Such a DLC is only a handful of tiny `.tres` files, without shipping a single texture again.
@export var enemy_health_scale := 1.0
@export var enemy_damage_scale := 1.0
@export var reward_scale := 1.0
