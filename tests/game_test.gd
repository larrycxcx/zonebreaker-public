class_name GameTest
extends RefCounted
## Base class for behaviour tests. Every method starting with `test_` in a subclass is one case, found and run automatically by `run_tests.gd`.
##
## These are "run it and look at the result" integration tests: they really instantiate the main scene, really simulate key presses and really wait for physics frames,
## so they catch problems a plain syntax check cannot (wrong collision layers, rays that miss, state machines that get stuck, etc.).
## For this they read and write private members of the objects under test (`_primary.cooldown_left` and so on) — on purpose;
## it is cheaper than opening up a pile of public interfaces in the game code just for tests.

## Every input action the project should define; test_input_actions_exist checks them one by one.
const ACTIONS := ["move_left", "move_right", "jump", "crouch", "sprint", "aim_up", "aim_down", "shoot", "switch_weapon", "ultimate"]

## Numbers are RPG-style (players 120 health, enemies from 20), and tests are written in "hits":
## one enemy hit on a level 1 player costs HIT (dead in 3 hits), one player bullet on an enemy costs SHOT (a patroller dies in 2).
const HIT := 40
const SHOT := 10

## Injected by the runner. In a SceneTree script `await tree.physics_frame` is what advances physics.
var tree: SceneTree
var main: Node
var player: Player
## Player 2 in co-op (only present when reset_scene is given players = 2), null when playing alone.
var player2: Player
var results: Array[Dictionary] = []
## The event names GameEvents reported during this case, in order. Cleared by reset_scene().
var events: Array[StringName] = []


## Whether the third-party art is present (the public build strips it, see `tools/export_public.py`). The cyberpunk pack is used as the marker: every other pack falls back to it.
const THIRD_PARTY_ART := "res://skins/cyberpunk/cyberpunk_skin.tres"

## Whether this case was skipped (the runner reads it and counts it as "skipped" rather than "passed").
var skipped := false


## **This case tests the art itself** (sprites, font, a zone's pack): skip it when the art is missing and return true.
## Usage: `if needs_art(): return` as the first line of the case. Do not add it to cases that only test rules — the public build has to guard the rules too.
func needs_art() -> bool:
	if ResourceLoader.exists(THIRD_PARTY_ART):
		return false
	skipped = true
	return true


func check(label: String, ok: bool, detail := "") -> void:
	results.append({"label": label, "ok": ok, "detail": detail})


func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## Press and release (for "once per press" actions: jump, switching weapons, up / down and confirm in menus).
## **Hold it for at least two frames**: a press simulated by `Input.action_press()` only counts as just_pressed on **the next physics frame**,
## and released after one frame the key is already up when the check comes round, so nothing happens.
func tap(action: StringName) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(1)


## Release every game action (skipping the engine's own ui_*).
## Walks the InputMap directly instead of the ACTIONS list: if a new action was added but not registered,
## a key pressed by one case would stay held into the following cases (aiming up just fell into this).
func release_all_input() -> void:
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			Input.action_release(action)


## Load a fresh copy of the main scene.
## All enemies are cleared by default: patrollers walk the whole floor, and when testing pure controls without clearing them,
## the player teleported over takes contact damage and gets knocked away, and a whole chain of assertions fails mysteriously.
## The upright walls under Level/Walls are removed by default too: walls block movement, bullets and sight, while most cases test mechanics unrelated to walls
## and should not fail because cover in the level was moved around. Cases testing walls themselves pass keep_walls = true.
## If `skin` is given the stage is loaded with it (characters install their look from the current pack in _ready, so it has to be set before loading);
## without it the default pack is restored.
## `scene` defaults to **the test level** (`main.tscn`, 1280 wide, one continuous floor); real stages pass their own path.
## `stage` is this stage's strength (multipliers for enemy health / damage / rewards) and **must be set before loading** —
## enemies scale by it in `_ready`. Empty = all multipliers 1, which is what the old cases run at.
func reset_scene(keep_enemies := false, keep_walls := false, skin: SkinPack = null, players := 1,
		scene := "res://scenes/main.tscn", stage: LevelInfo = null) -> void:
	release_all_input()
	# **Pad bindings are changed in the InputMap** (`Session.claim_pads()`), which is global state:
	# if a case claimed pads and it is not restored, it leaks into every following case.
	Session.reset_pads()
	free_scene()
	# The ultimate pauses the whole tree: if a case fails halfway before it resumes, the pause must not be carried into the next case.
	tree.paused = false
	# The skin pack is global state: a case that switched packs and failed before switching back would affect every case after it, so the default pack is restored every time.
	Skins.use(skin if skin != null else Skins.default_skin())
	# "Which stage is being played" is global state too (enemies scale by it): reset to "no stage" = all multipliers 1
	Stage.use(stage)
	# Progression is global state too: every case starts from a new game (level 1, starting weapons), without reading or writing the player's real save
	Progress.persist = false
	Progress.new_game()
	# The number of players is global state too (Session); set it in every case, single player by default
	Session.set_player_count(players)
	events.clear()
	if not GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.connect(_record_event)
	main = load(scene).instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	player2 = main.get_node_or_null("Player2")
	if not keep_enemies:
		for enemy in main.get_node("Enemies").get_children():
			enemy.free()
	if not keep_walls:
		for wall in main.get_node("Level/Walls").get_children():
			wall.free()
	await frames(2)


## Put up a temporary solid upright wall in the level (the same way as the level's walls: platform.tscn, 16px wide, standing on the ground) and return it.
## Used when testing the "wall" mechanic itself, so it does not depend on where or whether the level has walls (Wall3 was removed to try out the boss difficulty).
func add_wall(x: float, height: float, wall_name := "TestWall") -> Platform:
	var w: Platform = load("res://scenes/platform.tscn").instantiate()
	w.name = wall_name
	w.position = Vector2(x, 320.0 - height)
	w.size = Vector2(8, height)
	main.get_node("Level/Walls").add_child(w)
	return w


## Make the camera catch up right after teleporting the player. The camera follows **after** the physics update each frame, so on the teleport frame enemies still see last frame's view —
## enemies "see the player when on screen", so on that frame they might spot the player by mistake (and D would come chasing with its 2-second memory).
func snap_camera() -> void:
	var camera := camera_rig()
	if camera != null:
		camera._physics_process(0.0)
		camera.force_update_scroll()


## The camera shared by the level (following the midpoint of the two players, no longer hung on the player).
func camera_rig() -> CameraRig:
	return main.get_node_or_null("Camera2D") as CameraRig


## The enemies in the level (only real enemies). Enemy bullets and grenades also hang under Enemies (they finish their flight after the enemy dies),
## and enemies fire as soon as they are on screen, so right after loading there may be bullets under Enemies — use this to walk the enemies, not get_children() directly.
func enemies() -> Array:
	return main.get_node("Enemies").get_children().filter(func(node: Node) -> bool: return node is Enemy)


## Keep only the enemies with the given names and remove all the rest.
## Every enemy shoots now, so testing one enemy means clearing the others, or their bullets would contaminate the result.
func keep_only_enemies(names: Array) -> void:
	for enemy in main.get_node("Enemies").get_children():
		if not names.has(String(enemy.name)):
			enemy.free()


func _record_event(event: StringName, _source: Node) -> void:
	events.append(event)


func free_scene() -> void:
	release_all_input()
	tree.paused = false
	if GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.disconnect(_record_event)
	if main != null and is_instance_valid(main):
		main.free()
	main = null
	player = null


## The block with this name in a character's look (gun, barrel and so on). Looks live in the Appearance on `Visual`.
func art(actor: Node, art_name: String) -> CanvasItem:
	return actor.get_node("Visual").get_node_or_null(NodePath(art_name)) as CanvasItem


## The gun barrel on an enemy that turns with its aim (set by turning_gun on the appearance layer).
func turning_gun(enemy: Enemy) -> Control:
	var appearance: Appearance = enemy.get_node("Visual")
	return appearance.get_node_or_null(appearance.turning_gun) as Control


## The keyboard keys bound to an action (physical_keycode), ignoring pad bindings.
func keyboard_keys(action: StringName) -> Array:
	var keys := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	return keys


## Collect the live bullets in play by collision layer (4 = player bullets, 16 = enemy bullets).
## Bullets vanish as soon as they hit, so "did it fire" has to be sampled frame by frame, not counted afterwards.
func bullets(layer: int, node: Node = null) -> Array:
	var found := []
	for child in (node if node != null else main).get_children():
		if child is Bullet and (child as Bullet).collision_layer == layer:
			found.append(child)
		found.append_array(bullets(layer, child))
	return found
