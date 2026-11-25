extends GameTest
## Sound: the event bus → skin pack → player chain, and skin packs replacing sounds.
## The first part confirms scene by scene that "the game really reports this event"; the last case checks
## that every event in SkinPack.SOUND_EVENTS was actually triggered by some scene — so the list and the game cannot drift apart.

const DEFAULT_SKIN_DIR := "res://skins/default/"

## Events actually seen in each scene, accumulated across cases (the cases of a suite share one instance).
var covered := {}


## Assert that these events all happened, and record them in covered.
func expect_events(expected: Array, context: String) -> void:
	for event in expected:
		var seen := events.has(event)
		check("%s reports %s" % [context, event], seen, "events: %s" % [events])
		if seen:
			covered[event] = true


func _only(enemy_name: String) -> Node:
	keep_only_enemies([enemy_name])
	# In the two frames of loading, enemies on screen may already have fired: clear those events and look only at this one enemy's
	events.clear()
	var enemy: Enemy = main.get_node("Enemies/" + enemy_name)
	enemy._fire_timer = 0.0 # and do not carry over that shot's cooldown either
	enemy._burst_left = 0
	return enemy


# ---------------------------------------------------------------- Structure

func test_audio_setup() -> void:
	if needs_art(): return
	await reset_scene()
	for autoload in ["GameEvents", "Skins", "Sfx"]:
		check("autoload %s is running" % autoload, tree.root.has_node(autoload))
	check("there is an SFX bus", AudioServer.get_bus_index(&"SFX") > 0)
	var players := Sfx.get_children().filter(func(c): return c is AudioStreamPlayer)
	check("Sfx has a pool of players", players.size() == Sfx.POOL_SIZE, str(players.size()))
	check("all of them play on the SFX bus", players.all(func(p): return p.bus == &"SFX"))
	# Which pack the game starts with is decided by the project settings (the cyberpunk pack now). Whatever it points to,
	# the sounds must be found — if not, the pack's fallback chain is broken.
	var startup := load(ProjectSettings.get_setting(Skins.SETTING)) as SkinPack
	check("the project setting points at a real skin pack", startup != null,
		str(ProjectSettings.get_setting(Skins.SETTING)))
	if startup != null:
		for event: StringName in SkinPack.SOUND_EVENTS:
			check("the startup skin can find %s" % event, startup.find_sound(event) != null)
	check("tests run on the default skin", Skins.current != null and Skins.current.resource_path == Skins.DEFAULT_SKIN)


func test_default_skin_has_every_sound() -> void:
	await reset_scene()
	var skin := Skins.default_skin()
	for event in SkinPack.SOUND_EVENTS:
		var stream := skin.find_sound(event)
		check("default skin has %s" % event, stream != null and stream.resource_path.begins_with(DEFAULT_SKIN_DIR), stream.resource_path if stream else "missing")
	check("default skin has no sounds beyond the event list", skin.sounds.keys().all(func(e): return SkinPack.SOUND_EVENTS.has(e)), str(skin.sounds.keys()))
	var shoot := skin.find_sound(&"player_shoot") as AudioStreamRandomizer
	check("player_shoot takes turns over 3 variants", shoot != null and shoot.streams_count == 3 and shoot.playback_mode == AudioStreamRandomizer.PLAYBACK_SEQUENTIAL)


func test_every_sound_file_is_used() -> void:
	# Every wav the generator outputs must be used by the default pack, with no orphans; and every file the pack references must exist.
	await reset_scene()
	var used := {}
	for stream in Skins.default_skin().sounds.values():
		if stream is AudioStreamRandomizer:
			for i in stream.streams_count:
				used[stream.get_stream(i).resource_path] = true
		else:
			used[stream.resource_path] = true
	var files := Array(DirAccess.get_files_at(DEFAULT_SKIN_DIR + "sfx")).filter(func(f): return f.ends_with(".wav")).map(func(f): return DEFAULT_SKIN_DIR + "sfx/" + f)
	check("31 sound files in the default skin", files.size() == 31, str(files.size()))
	for f in files:
		check("%s is used by the skin" % f.get_file(), used.has(f))
	check("the skin references no missing files", used.keys().all(func(p): return FileAccess.file_exists(p)))


# ---------------------------------------------------------------- The game really reports these events

func test_player_events() -> void:
	await reset_scene()
	player.global_position = Vector2(60, 304)
	player.facing = -1
	player._visual.scale.x = -1
	await frames(10)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	await frames(60)
	player.current_slot().cooldown_left = 0.0
	Input.action_press("shoot") # Firing left against the left wall
	await frames(2)
	Input.action_release("shoot")
	await frames(10)
	expect_events([&"jump", &"player_shoot", &"bullet_impact"], "jumping and shooting a wall")


func test_stamina_event() -> void:
	await reset_scene()
	player.global_position = Vector2(740, 304)
	player.stamina = 6.0
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(20)
	expect_events([&"stamina_exhausted"], "running out of stamina")
	check("stamina_exhausted is reported once, not every frame", events.count(&"stamina_exhausted") == 1, str(events.count(&"stamina_exhausted")))


func test_player_hurt_death_and_game_over() -> void:
	await reset_scene()
	await frames(5)
	for i in 3:
		player._invincible_timer = 0.0
		player.take_damage(HIT, player.global_position + Vector2(40, 0))
		await frames(2)
	# game_over is now **reported immediately** (`game_over_delay` is now 0): the sound goes through the Sfx singleton,
	# and the screen popping up does not cut it off, so there is no need to wait for the death sound first
	await frames(4)
	expect_events([&"player_hurt", &"player_death", &"game_over"], "losing all health")
	check("hurt twice before dying", events.count(&"player_hurt") == 2, str(events.count(&"player_hurt")))


func test_enemy_hit_and_death() -> void:
	await reset_scene(true)
	var walker: EnemyWalker = _only("WalkerA")
	walker.global_position = Vector2(500, 304)
	walker.move_speed = 0.0
	player.global_position = Vector2(420, 304)
	player.facing = 1
	player._visual.scale.x = 1
	player._invincible_timer = 1000.0
	await frames(5)
	for i in 2:
		player._invincible_timer = 1000.0
		player.current_slot().cooldown_left = 0.0
		player._shoot(Vector2.RIGHT)
		await frames(20)
	expect_events([&"enemy_hit", &"enemy_death"], "shooting a 2-health walker twice")


func test_walker_shot() -> void:
	await reset_scene(true)
	var walker: EnemyWalker = _only("WalkerA")
	walker.global_position = Vector2(500, 304)
	walker.move_speed = 0.0
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(360, 304)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"enemy_shoot"], "a walker firing")
	check("walkers do not use the turret or flyer sound", not events.has(&"turret_shoot") and not events.has(&"flyer_shoot"))


func test_turret_shot() -> void:
	await reset_scene(true)
	var turret: EnemyTurret = _only("Turret1")
	turret.global_position = Vector2(1000, 304)
	player.global_position = Vector2(860, 304)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"turret_shoot"], "a turret firing")
	check("the turret does not use the walker sound", not events.has(&"enemy_shoot"))


func test_enemy_prone_event() -> void:
	# Only C goes prone after the player (the turret does not).
	await reset_scene(true)
	var c: EnemyWalker = _only("WalkerC")
	c.global_position = Vector2(1000, 304)
	c.move_speed = 0.0
	c.facing = -1
	c._apply_facing()
	player.global_position = Vector2(860, 304)
	Input.action_press("crouch")
	for i in 60:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"enemy_prone"], "C lying down with the player")
	check("enemy_prone is reported once, not every frame", events.count(&"enemy_prone") == 1, str(events.count(&"enemy_prone")))
	# set_prone() is public: calling it again on an enemy already prone must not report it again.
	c.set_prone(true)
	check("set_prone on an already prone enemy does not report again", events.count(&"enemy_prone") == 1, str(events.count(&"enemy_prone")))


func test_flyer_shot() -> void:
	await reset_scene(true)
	var flyer: EnemyFlyer = _only("FlyerE")
	flyer.set_anchor(Vector2(400, 88))
	flyer.move_speed = 0.0
	player.global_position = Vector2(400, 304)
	for i in 20:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"flyer_shoot"], "E firing down")


func test_chaser_alert() -> void:
	await reset_scene(true)
	var d: EnemyChaser = _only("ChaserD")
	d.global_position = Vector2(500, 304)
	player.global_position = Vector2(1120, 304)
	snap_camera()
	await frames(10)
	check("no alert while D has not seen the player", not events.has(&"chaser_alert"))
	player.global_position = Vector2(360, 304)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"chaser_alert"], "D spotting the player")
	check("the alert sounds once, not every frame", events.count(&"chaser_alert") == 1, str(events.count(&"chaser_alert")))


func test_grenade_events() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(10)
	player.switch_weapon()
	player.current_slot().cooldown_left = 0.0
	Input.action_press("shoot")
	await frames(1)
	Input.action_release("shoot")
	await frames(90)
	expect_events([&"weapon_switch", &"grenade_throw", &"grenade_bounce", &"explosion"], "switching to grenades and throwing one")


func test_ultimate_events() -> void:
	await reset_scene()
	await frames(5)
	Input.action_press("ultimate")
	await frames(2)
	Input.action_release("ultimate")
	await frames(135) # Freezes for 2 seconds
	expect_events([&"ultimate_start", &"ultimate_blast"], "using the ultimate weapon")


func test_boss_appear_event() -> void:
	await reset_scene(true)
	keep_only_enemies(["BossMissile"])
	player.global_position = Vector2(1120, 304)
	await frames(10)
	expect_events([&"boss_appear"], "a boss coming on screen")


func test_level_clear_event() -> void:
	# The boss falling = this stage is cleared. Killing the boss used to do nothing, and a stage had only one way out — everyone dying.
	await reset_scene(true)
	keep_only_enemies(["BossMissile"])
	var boss: Boss = main.get_node("Enemies/BossMissile")
	player.global_position = Vector2(1120, 304)
	await frames(10)
	boss.take_damage(boss.max_health)
	await frames(4)
	expect_events([&"level_clear"], "the boss going down")
	# The results screen only pops up after 1.5 seconds; do not wait for it here. Clear the pause so it is not carried into the next case
	tree.paused = false


# ---------------------------------------------------------------- Player and skin packs

func test_sfx_plays_the_skin_sound() -> void:
	await reset_scene()
	var played := []
	var record := func(event: StringName, stream: AudioStream) -> void: played.append([event, stream])
	Sfx.sound_played.connect(record)
	GameEvents.report(&"jump")
	Sfx.sound_played.disconnect(record)
	check("reporting jump plays one sound", played.size() == 1, str(played.size()))
	if played.size() == 1:
		check("it is the skin's jump sound", played[0][1] == Skins.current.find_sound(&"jump"), str(played[0][1].resource_path))
	check("and it is actually playing", Sfx.playing_count(&"jump") >= 1)


func test_a_custom_skin_replaces_only_what_it_provides() -> void:
	await reset_scene()
	var custom := SkinPack.new()
	custom.display_name = "test skin"
	var replacement: AudioStream = load("res://skins/default/sfx/enemy_death.wav")
	custom.sounds[&"jump"] = replacement
	custom.fallback = Skins.default_skin()
	Skins.use(custom)
	var played := {}
	var record := func(event: StringName, stream: AudioStream) -> void: played[event] = stream
	Sfx.sound_played.connect(record)
	GameEvents.report(&"jump")
	GameEvents.report(&"player_shoot")
	Sfx.sound_played.disconnect(record)
	check("the custom skin's jump sound plays", played.get(&"jump") == replacement)
	check("sounds it does not provide fall back to the default skin", played.get(&"player_shoot") == Skins.default_skin().find_sound(&"player_shoot"))


func test_a_skin_missing_a_sound_stays_silent() -> void:
	# No fallback pack and a sound not provided: silent, no error (the runner counts any SCRIPT ERROR as a failure).
	await reset_scene()
	Skins.use(SkinPack.new())
	var played := []
	var record := func(event: StringName, _stream: AudioStream) -> void: played.append(event)
	Sfx.sound_played.connect(record)
	GameEvents.report(&"jump")
	Sfx.sound_played.disconnect(record)
	check("nothing plays for a sound the skin does not have", played.is_empty())


func test_same_sound_is_capped() -> void:
	await reset_scene()
	for i in 10:
		GameEvents.report(&"bullet_impact")
	check("at most %d copies of one sound at once" % Sfx.MAX_PER_EVENT, Sfx.playing_count(&"bullet_impact") == Sfx.MAX_PER_EVENT, str(Sfx.playing_count(&"bullet_impact")))
	GameEvents.report(&"jump")
	check("other sounds still get a player", Sfx.playing_count(&"jump") >= 1)


func test_going_down_and_being_picked_up_have_their_own_sounds() -> void:
	# The two co-op-only moments: going down waiting for help, and being pulled up by the partner. They never happen alone (out of health you just die).
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(500, 304)
	await frames(3)
	events.clear()
	player2.take_damage(player2.max_health)
	await frames(2)
	expect_events([&"player_down"], "going down")
	check("and it is heard", Sfx.playing_count(&"player_down") >= 1)
	player.global_position = player2.global_position
	await frames(3)
	expect_events([&"player_revive"], "being picked up")
	check("and that is heard too", Sfx.playing_count(&"player_revive") >= 1)


func test_the_menu_clicks() -> void:
	# Pause menu: opening, cursor up / down, going back each have their own sound. The menu's own behaviour is tested in test_menus.gd.
	await reset_scene()
	events.clear()
	await tap(&"pause")
	expect_events([&"menu_select"], "opening the pause menu")
	await tap(&"aim_down")
	expect_events([&"menu_move"], "moving the cursor")
	await tap(&"cancel")
	expect_events([&"menu_back"], "backing out")
	check("and the level is running again", not tree.paused)


func test_sounds_outlive_the_level() -> void:
	# After dying the stage reloads; game_over has to keep playing to the end, so the player cannot hang under the stage.
	await reset_scene()
	GameEvents.report(&"game_over")
	free_scene()
	await frames(2)
	check("game_over keeps playing after the level is freed", Sfx.playing_count(&"game_over") >= 1)
	await reset_scene() # Leave a scene for the runner to free at the end


# ---------------------------------------------------------------- The list and the game agree

func test_the_hammer_and_the_second_boss_phase_have_sounds() -> void:
	# These two only appear in stage 2 (the test level has neither), so place one on the test level here.
	# Every event in the list has to really fire in the game — that is what the final case below checks.
	var pack := load("res://skins/industrial/industrial_skin.tres") as SkinPack
	await reset_scene(false, true, pack)
	var hammer := (load("res://scenes/enemy_2_d.tscn") as PackedScene).instantiate() as EnemyHammer
	main.get_node("Enemies").add_child(hammer)
	hammer.global_position = Vector2(500, 304)
	hammer.contact_damage = 0
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, 304)
	player.health = 9999
	snap_camera()
	events.clear()
	for i in 180:
		await tree.physics_frame
		player.health = 9999
		if events.has(&"hammer_smash"):
			break
	expect_events([&"hammer_smash"], "the hammer swing starts")

	await reset_scene(false, true, pack)
	var boss := (load("res://scenes/boss_2.tscn") as PackedScene).instantiate() as BossOperator
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(500, 170)
	boss._home = boss.global_position
	await frames(2)
	boss.appear()
	events.clear()
	# **A scratch should not switch gear**: hit it once first and confirm nothing is reported
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a scratch does not flip it", not events.has(&"boss_enrage") and not boss.is_enraged())
	# **Do not kill it in one hit**: dead, it never switches gear (only reported while `health > 0`), and that case would wait in vain
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("setup: it is hurt but alive", boss.health > 0, str(boss.health))
	expect_events([&"boss_enrage"], "Boss drops below half health")


func test_zz_every_listed_event_happens_in_game() -> void:
	# Last in line (cases run in declaration order): the scenes above have covered every event in the list.
	await reset_scene()
	for event in SkinPack.SOUND_EVENTS:
		check("%s is triggered by gameplay" % event, covered.has(event))
