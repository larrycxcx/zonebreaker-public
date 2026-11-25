class_name SkinPack
extends Resource
## A skin pack: a whole set of game assets that can be swapped as one. Only sound effects for now; step 4 adds sprites, backdrops and music.
##
## Making a new skin pack: create a SkinPack resource (.tres) in the editor with `fallback` pointing at the default pack
## (res://skins/default/default_skin.tres), then fill in only the events you want to replace under `sounds` —
## events left out keep using the fallback pack's sounds. Then point the project setting game/skin at the new .tres.
## For several variants of one event played in turn / at random, use an AudioStreamRandomizer as that sound (the default pack's player_shoot does this).

## Every sound event the game emits, and when it fires. This is the skin pack's "interface contract":
## whoever makes the assets prepares sounds from this list; test_audio.gd checks that the default pack covers every entry here,
## and that every entry really fires in the game. When adding an event change both.
const SOUND_EVENTS := {
	&"player_shoot": "the player fires a shot",
	&"jump": "the player jumps",
	&"player_hurt": "the player loses health (without dying)",
	&"player_death": "the player's health reaches zero",
	&"player_down": "co-op: the player's health reaches zero but they can still be saved, lying on the ground waiting for the partner",
	&"player_revive": "co-op: the partner walks over and pulls the downed player up",
	&"menu_move": "the cursor moves up / down in a menu",
	&"menu_select": "an item is confirmed in a menu (opening the pause menu counts too)",
	&"menu_back": "going back a level in a menu (closing the pause menu counts too)",
	&"stamina_exhausted": "the player runs out of stamina",
	&"enemy_shoot": "patroller A/B/C fires (once per bullet, several times for B's burst)",
	&"turret_shoot": "a turret fires",
	&"flyer_shoot": "E fires downward",
	&"enemy_hit": "an enemy is hit but not killed",
	&"enemy_death": "an enemy is destroyed",
	&"enemy_prone": "enemy C goes prone after the player (turrets never go prone)",
	&"chaser_alert": "D spots the player and starts charging",
	&"bullet_impact": "any bullet hits something solid such as a wall, the ground or a crawl passage",
	&"game_over": "after the player dies, shows GAME OVER",
	&"level_clear": "Boss falls; the stage is cleared",
	&"grenade_throw": "the player throws a grenade",
	&"grenade_bounce": "a grenade bounces off the ground or a wall",
	&"explosion": "a grenade explodes",
	&"weapon_switch": "the player switches weapons",
	&"ultimate_start": "the player fires the ultimate (the freeze starts)",
	&"ultimate_blast": "the ultimate destroys the enemies on screen (the freeze ends)",
	&"boss_appear": "Boss appears (first time on screen)",
	&"boss_enrage": "Boss drops below half health and switches tactics (reported once)",
	&"hammer_smash": "a hammer enemy starts its swing (a few frames before it hits the ground)",
}

## Purposes of the background music, and when each plays.
const MUSIC_KEYS := {
	&"intro": "main menu",
	&"level": "in a stage (starts when the stage loads; a restart after dying does not start it over)",
	&"boss": "Boss has appeared",
}

## Keys of every character appearance, and who each one is. Whoever makes the assets prepares appearance scenes from this list (root node with the Appearance script).
## A custom pack only fills in what it replaces; characters left out use the default look in their own scene (the placeholder blocks for now).
## **This list is documentation for whoever makes the assets, not a whitelist**: at run time the lookup is `appearances.get(key)` —
## a dictionary that accepts any key. Each of the 23 stages brings its own enemies and boss and new keys keep coming;
## as a whitelist, "adding an enemy" would mean editing this constant (and a DLC could not edit it at all).
const APPEARANCE_KEYS := {
	&"biker": "Selectable character: Biker",
	&"punk": "Selectable character: Punk",
	&"cyborg": "Selectable character: Cyborg",
	&"walker": "the patroller base scene (never placed in levels directly; the three below are)",
	&"1_a": "patroller A (level shots only)",
	&"1_b": "patroller B (bursts, shoots diagonally)",
	&"1_c": "patroller C (long range, shoots diagonally, goes prone)",
	&"1_f": "enemy F (patroller that throws grenades)",
	&"1_g": "turret",
	&"1_e": "enemy E (flying)",
	&"1_d": "enemy D (chaser)",
	&"1_boss": "Boss A",
	# Projectiles (the appearance's root also has Appearance; bullets get aim(flight direction) and the pack picks an image by direction, see ProjectileAppearance)
	&"player_bullet": "the player's bullets",
	&"enemy_bullet": "enemy bullets (patrollers)",
	&"boss_bullet": "Boss A missile-fan bullets",
	&"turret_bullet": "turret shells",
	&"flyer_bullet": "E downward bullets",
	&"player_grenade": "the player's grenades",
	&"enemy_grenade": "F batted grenades",
	# Terrain (used by platform.tscn; the appearance scene's root is an appearance with fit(size), such as TerrainAppearance)
	&"terrain_ground": "ground",
	&"terrain_ledge": "floating one-way platform",
	&"terrain_stone": "solid blocks such as walls and crawl passage roofs",
}

## Keys of every effect. Ones left out use the default scenes set on the Fx node.
const EFFECT_KEYS := {
	&"muzzle_flash": "muzzle flash when firing",
	&"hit_spark": "a bullet hits a character",
	&"impact_spark": "a bullet hits a wall or the ground",
	&"explosion": "a grenade explodes",
}

## Name shown in the editor.
@export var display_name := ""
## Event name → sound.
@export var sounds: Dictionary[StringName, AudioStream] = {}
## Character appearances: skin key (`APPEARANCE_KEYS`) → appearance scene, whose root must have the `Appearance` script.
@export var appearances: Dictionary[StringName, PackedScene] = {}
## Effects: effect key (`EFFECT_KEYS`) → scene.
@export var effects: Dictionary[StringName, PackedScene] = {}
## Stage backdrop (a few layers of parallax art, display only). Empty means no backdrop; the project's clear colour shows.
@export var backdrop: PackedScene
## Lighting layer: a layer over the backdrop, scenery and terrain and under the enemies and players (the root is usually a `ScreenLight`), display only.
## Empty means none.
@export var lighting: PackedScene
## HUD appearance (root with a script such as SpriteHud providing show_health / show_stamina / …). Empty uses the HUD's own placeholder blocks.
@export var hud: PackedScene
## Background music: purpose (`MUSIC_KEYS`) → track. A purpose with no track goes silent (the default pack has none).
@export var music: Dictionary[StringName, AudioStream] = {}
## Where to look for things this pack does not have. Custom packs usually point at the default pack; the default pack leaves it empty.
@export var fallback: SkinPack


## Find the sound for an event: look here first, then ask the fallback pack; null if neither has it.
func find_sound(event: StringName) -> AudioStream:
	var stream: AudioStream = sounds.get(event)
	if stream != null:
		return stream
	return fallback.find_sound(event) if fallback != null else null


## Find a character's appearance scene: look here first, then ask the fallback pack; null if neither has it (= use the one built into the character's scene).
func find_appearance(key: StringName) -> PackedScene:
	var scene: PackedScene = appearances.get(key)
	if scene != null:
		return scene
	return fallback.find_appearance(key) if fallback != null else null


## Find the backdrop scene: look here first, then ask the fallback pack.
func find_backdrop() -> PackedScene:
	if backdrop != null:
		return backdrop
	return fallback.find_backdrop() if fallback != null else null


## Find the lighting layer: look here first, then ask the fallback pack (same rule as the backdrop — the lighting comes from wherever the backdrop comes from).
func find_lighting() -> PackedScene:
	if lighting != null:
		return lighting
	return fallback.find_lighting() if fallback != null else null


## Find the background music for a purpose: look here first, then ask the fallback pack.
func find_music(key: StringName) -> AudioStream:
	var stream: AudioStream = music.get(key)
	if stream != null:
		return stream
	return fallback.find_music(key) if fallback != null else null


## Find a file in the pack (relative to the pack folder, e.g. `biker/portrait.png`): look here first, then ask the fallback pack.
## **Not every pack holds the full set** — each stage's pack only has what is unique to that stage, while characters, UI and so on are shared by all 23 stages
## and only exist once, in the pack at the bottom. Portraits were first built from the current pack's folder directly,
## so returning to the main menu after clearing stage 2 the current pack was the industrial one, which has no character folders, and all three portraits were blank.
func find_file(relative: String) -> String:
	if not resource_path.is_empty():
		var path := "%s/%s" % [resource_path.get_base_dir(), relative]
		if ResourceLoader.exists(path):
			return path
	return fallback.find_file(relative) if fallback != null else ""


## Find the HUD appearance: look here first, then ask the fallback pack.
func find_hud() -> PackedScene:
	if hud != null:
		return hud
	return fallback.find_hud() if fallback != null else null


## Find the scene for an effect, same rule as above.
func find_effect(key: StringName) -> PackedScene:
	var scene: PackedScene = effects.get(key)
	if scene != null:
		return scene
	return fallback.find_effect(key) if fallback != null else null
