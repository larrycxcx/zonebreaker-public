class_name CharacterLook
extends Resource
## The card of a selectable character: skin key, what it is called, where it sits in the order.
##
## The character list comes from **scanning the `characters/` directory** (see `Catalog`).
## **It does not scan the skin packs**: a pack mixes in `backdrop`, `enemies`, `ui` and other folders that are not characters,
## and the default pack has no character folders at all (the placeholder blocks need no sprites), so the scan would come back empty.

## Skin key: both the player's `skin_key` and the `look` in the save use it,
## the pack finds the appearance scene by it (`SkinPack.appearances`) and the sprites find their folder by it.
@export var key := &""
## What the UI calls it. Not shown yet; kept for a future character select screen.
@export var display_name := ""
## Position in the order: left to right among the three portraits in character setup.
@export var order := 0
