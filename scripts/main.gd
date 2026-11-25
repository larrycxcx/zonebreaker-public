extends Node2D
## Level root node: restarts the stage when the player dies.

## How long after everyone is down "retry / main menu" pops up. **0.5 seconds = the length of the death animation**;
## it used to be 1.2 seconds and playtesters found the wait boring, but it cannot be 0 either — that screen freezes the whole tree,
## so the moment you got shot everything would freeze and not a single frame of the fall would play.
@export var respawn_delay := 0.5
## How long after everyone is down game_over is reported (**0, immediately**). The sound is played by the Sfx singleton (`PROCESS_MODE_ALWAYS`),
## so the screen popping up does not cut it off and there is no need to wait for it.
@export var game_over_delay := 0.0

## How far beside player 1 player 2 spawns.
@export var second_player_offset := Vector2(-28, 0)
## Falling below this height counts as falling out of the stage (the bottom of a pit). The ground is at y=320 and the bottom of the view at 360;
## only 40px further down counts — so running along the ground never triggers it, and falling into a pit is fatal straight away.
@export var fall_y := 400.0
## How far below the bottom of the view counts as falling out in vertical stages: 40, the same as horizontal stages (ground 320, view bottom 360, line 400).
const FALL_MARGIN := 40.0
## How far below the bottom of the view enemies left behind are removed (a bit lower than the players' line: one just off screen might still be hit).
const LEFT_BEHIND := 120.0
## How long after the boss falls the results are shown: let the explosion and screen shake finish.
@export var clear_delay := 1.5

@onready var _player: Player = $Player
## The layer that lets the player choose "retry / main menu" after everyone is down. Without one in the level it restarts automatically as before.
@onready var _death: DeathScreen = get_node_or_null("DeathScreen")
## The layer that shows the results after a clear. Without one in the level there is nothing to do (you just stand there after clearing).
@onready var _clear: ClearScreen = get_node_or_null("ClearScreen")
## This stage has ended (everyone down or cleared). In co-op both players may die on the same frame, and without this game_over would be reported twice;
## it also keeps both screens from popping up when the last player dies at the same moment the boss falls.
var _over := false
## XP, money and level of each seat on entering the stage — the results screen uses them to work out "how much this stage earned".
var _started: Array[Dictionary] = []


## In stages built from grid maps the visuals come from the tiles (`FrontTiles`) and the collision platforms are hidden. **When the tile art is missing**
## (the public build strips third-party art) nothing is drawn and the ground is invisible, so reveal those platforms
## and use their own placeholder look (plain coloured blocks) as terrain — the rules do not change at all, it just falls back to blocks.
func _show_bare_terrain() -> void:
	var tiles := get_node_or_null("FrontTiles") as TileArt
	if tiles == null or tiles.atlas != null:
		return
	# Only reveal the platforms under `Level`: the invisible cover on top of a ladder (hung under the ladder) should never be drawn
	for node in get_node("Level").get_children():
		if node is Platform:
			(node as Platform).visible = true


func _ready() -> void:
	_add_players()
	_add_huds()
	_add_backdrop()
	_add_lighting()
	_show_bare_terrain()
	# The stage's music; on a restart after dying, if the same track is already playing it carries on instead of starting over (see Music)
	Music.play(&"level")
	for node in get_tree().get_nodes_in_group(&"player"):
		(node as Player).died.connect(_on_player_died)
	_remember_start()
	# A boss may be spawned mid-level, so wait on the bus for it to appear, then listen for its death
	GameEvents.boss_appeared.connect(_on_boss_appeared)


## In co-op put player 2 next to player 1: the same player scene with `player_index` = 1 (reads the p2_ inputs and uses its own progress).
func _add_players() -> void:
	if Session.player_count < 2:
		return
	var second := (load(_player.scene_file_path) as PackedScene).instantiate() as Player
	second.name = "Player2"
	second.player_index = 1
	# What it looks like is decided by the `look` in its progress (read in `Player._ready`), not here
	add_child(second)
	move_child(second, _player.get_index() + 1)
	second.global_position = _player.global_position + second_player_offset


## In co-op give player 2 its own HUD on the right side of the screen. The boss bar and death message are shared and only shown by the left HUD,
## otherwise the two would overlap (`shows_shared`).
func _add_huds() -> void:
	if Session.player_count < 2:
		return
	var hud := $HUD as CanvasLayer
	var second := (load(hud.scene_file_path) as PackedScene).instantiate()
	second.name = "HUD2"
	second.player_index = 1
	second.mirrored = true
	second.shows_shared = false
	add_child(second)


## If the current skin pack has a backdrop, put it at the very bottom (the first child is drawn first). Display only; without one the project's clear colour shows.
func _add_backdrop() -> void:
	var scene := Skins.backdrop()
	if scene == null:
		return
	var backdrop := scene.instantiate()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	move_child(backdrop, 0)


## If the current skin pack has a lighting layer, insert it **behind the terrain's front, in front of the enemies**: backdrop, scenery and terrain get tinted by it,
## while characters and bullets are drawn on top in their own colours (see `ScreenLight`). Without a `Level` it goes behind the backdrop.
func _add_lighting() -> void:
	var scene := Skins.lighting()
	if scene == null:
		return
	var light := scene.instantiate()
	light.name = "Lighting"
	var level := get_node_or_null("Level")
	add_child(light)
	move_child(light, level.get_index() + 1 if level != null else 1)


## It is only lost once nobody is left (the HUD asks the same question, so the check lives on `Player`).
func _anyone_left() -> bool:
	return Player.anyone_left(get_tree())


## Play time only counts in a stage: menus and pause do not count (when paused the whole tree stops and this does not run anyway).
func _process(delta: float) -> void:
	Progress.tick_playtime(delta)


## Clean up whatever fell into a pit. Players lose health and are brought back to where they last stood (`Player.fall_out()`); enemies `die()` as usual —
## luring a chasing D to the edge of a pit and pushing it in still pays XP (unattributed kills go to player 1, see `Progress`).
func _physics_process(_delta: float) -> void:
	var line := player_fall_line()
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		# Players who are down get brought back too: they have no health left to lose, but left at the bottom of a pit their partner could never reach them
		if player != null and (player.is_alive() or player.is_downed()) 				and player.global_position.y > line:
			player.fall_out()
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		# Ones already queued for deletion must not die again, or enemy_death fires twice and the reward is paid twice
		if enemy.global_position.y > fall_y:
			enemy.die()
		elif enemy.global_position.y > line + LEFT_BEHIND:
			# In vertical stages, ones left behind as the view scrolls away: **deleted quietly**, no XP and no death report —
			# the player did not kill them, and left alive they would snipe upward from off screen
			enemy.queue_free()


## The line below which a player has fallen out. In horizontal stages it is the fixed `fall_y`;
## in vertical stages (camera `only_up`) it follows the bottom of the view: once the view has scrolled up, falling off the bottom is final.
func player_fall_line() -> float:
	var rig := CameraRig.find(get_tree())
	if rig == null or not rig.only_up:
		return fall_y
	return minf(fall_y, rig.view_rect().end.y + FALL_MARGIN)


## On entering the stage record each seat's XP, money and level; the results screen works out the differences from them.
func _remember_start() -> void:
	_started.clear()
	for index in Session.player_count:
		var who := Progress.of(index)
		_started.append({"xp": who.xp, "money": who.money, "level": who.level})


func _on_boss_appeared(boss: Node2D) -> void:
	var it := boss as Boss
	# Killing the mid-level boss (`ends_level` off) does not clear the stage; keep going
	if it != null and it.ends_level and not it.died.is_connected(_on_boss_died):
		it.died.connect(_on_boss_died)


## The boss falling = this stage is cleared. Killing the boss used to do nothing,
## and a stage had only one way out — everyone dying; for 23 stages to connect there has to be "cleared".
func _on_boss_died() -> void:
	if _over:
		return
	_over = true
	GameEvents.report(&"level_clear", self)
	_unlock_next()
	await get_tree().create_timer(clear_delay).timeout
	if _clear != null:
		_clear.open(_results(), Catalog.index_of(Stage.current) + 1 < Catalog.count())


## Move progress on by one stage. **In co-op take the higher of the two**, then set both to it —
## when a veteran plays with a newcomer, the friend's new character unlocks along with them instead of replaying a dozen stages.
func _unlock_next() -> void:
	var at := Catalog.index_of(Stage.current)
	if at < 0:
		return                                    # The test level is not in the list; there is no progress to move on
	var unlocked := at + 2                        # Stages count from 0, unlocks count from 1
	for index in Session.player_count:
		unlocked = maxi(unlocked, Progress.of(index).reached)
	# **Only push up, never clamp down**: progress in a save must not be wiped after uninstalling a stage DLC
	#(when it is actually used, `MainMenu._unlocked()` cuts it to the number of stages available)
	for index in Session.player_count:
		var who := Progress.of(index)
		who.reached = maxi(who.reached, unlocked)
	Progress.save_game()


## How much each seat earned in this stage (the results screen lays it out, two columns in co-op).
func _results() -> Array:
	var out := []
	for index in Session.player_count:
		var who := Progress.of(index)
		var before: Dictionary = _started[index] if index < _started.size() else {}
		var gained := who.level - int(before.get("level", who.level))
		# A level-up resets XP and recounts it, which breaks the difference — add back the thresholds crossed, by "how many levels gained"
		var xp: int = who.xp - int(before.get("xp", 0))
		for step in gained:
			xp += who.balance.xp_to_next(int(before.get("level", 1)) + step)
		out.append({
			"name": who.character_name, "level": who.level, "levels_gained": gained,
			"xp": maxi(0, xp), "money": maxi(0, who.money - int(before.get("money", 0))),
		})
	return out


func _on_player_died() -> void:
	if _over or _anyone_left():
		return
	_over = true
	await get_tree().create_timer(game_over_delay).timeout
	GameEvents.report(&"game_over", self)
	await get_tree().create_timer(respawn_delay - game_over_delay).timeout
	if _death != null:
		_death.open()
		return
	# In tests the scene is instantiated by hand and there is no current_scene, so do not reload.
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()
