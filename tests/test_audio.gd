extends GameTest
## 音效：事件总线 → 素材包 → 播放器这条链路，以及素材包能替换声音。
## 前半部分逐个场景确认「游戏里真的会报告这个事件」，最后一条用例检查
## SkinPack.SOUND_EVENTS 里的每个事件都被某个场景实际触发过——清单和游戏不会各说各的。

const DEFAULT_SKIN_DIR := "res://skins/default/"

## 各场景实际观察到的事件，跨用例累计（同一组的用例共用一个实例）。
var covered := {}


## 断言这些事件都出现过，并记进 covered。
func expect_events(expected: Array, context: String) -> void:
	for event in expected:
		var seen := events.has(event)
		check("%s reports %s" % [context, event], seen, "events: %s" % [events])
		if seen:
			covered[event] = true


func _only(enemy_name: String) -> Node:
	keep_only_enemies([enemy_name])
	return main.get_node("Enemies/" + enemy_name)


# ---------------------------------------------------------------- 结构

func test_audio_setup() -> void:
	await reset_scene()
	for autoload in ["GameEvents", "Skins", "Sfx"]:
		check("autoload %s is running" % autoload, tree.root.has_node(autoload))
	check("there is an SFX bus", AudioServer.get_bus_index(&"SFX") > 0)
	var players := Sfx.get_children().filter(func(c): return c is AudioStreamPlayer)
	check("Sfx has a pool of players", players.size() == Sfx.POOL_SIZE, str(players.size()))
	check("all of them play on the SFX bus", players.all(func(p): return p.bus == &"SFX"))
	check("the project setting picks the default skin", ProjectSettings.get_setting(Skins.SETTING) == Skins.DEFAULT_SKIN)
	check("the default skin is loaded", Skins.current != null and Skins.current.resource_path == Skins.DEFAULT_SKIN)


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
	# 生成器输出的每个 wav 都要被默认包用上，不留孤儿文件；反过来包里引用的文件也都在。
	await reset_scene()
	var used := {}
	for stream in Skins.default_skin().sounds.values():
		if stream is AudioStreamRandomizer:
			for i in stream.streams_count:
				used[stream.get_stream(i).resource_path] = true
		else:
			used[stream.resource_path] = true
	var files := Array(DirAccess.get_files_at(DEFAULT_SKIN_DIR + "sfx")).filter(func(f): return f.ends_with(".wav")).map(func(f): return DEFAULT_SKIN_DIR + "sfx/" + f)
	check("16 sound files in the default skin", files.size() == 16, str(files.size()))
	for f in files:
		check("%s is used by the skin" % f.get_file(), used.has(f))
	check("the skin references no missing files", used.keys().all(func(p): return FileAccess.file_exists(p)))


# ---------------------------------------------------------------- 游戏里真的会报告这些事件

func test_player_events() -> void:
	await reset_scene()
	player.global_position = Vector2(30, 152)
	player.facing = -1
	player._visual.scale.x = -1
	await frames(10)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	await frames(60)
	player._fire_timer = 0.0
	Input.action_press("shoot") # 贴着左墙往左打
	await frames(2)
	Input.action_release("shoot")
	await frames(10)
	expect_events([&"jump", &"player_shoot", &"bullet_impact"], "jumping and shooting a wall")


func test_stamina_event() -> void:
	await reset_scene()
	player.global_position = Vector2(370, 152)
	player.stamina = 3.0
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
		player.take_damage(1, player.global_position + Vector2(20, 0))
		await frames(2)
	check("game_over waits for the death sound", not events.has(&"game_over"))
	await frames(40) # game_over_delay 0.5 秒
	expect_events([&"player_hurt", &"player_death", &"game_over"], "losing all health")
	check("hurt twice before dying", events.count(&"player_hurt") == 2, str(events.count(&"player_hurt")))


func test_enemy_hit_and_death() -> void:
	await reset_scene(true)
	var walker: EnemyWalker = _only("WalkerA")
	walker.global_position = Vector2(250, 153)
	walker.move_speed = 0.0
	player.global_position = Vector2(210, 152)
	player.facing = 1
	player._visual.scale.x = 1
	await frames(5)
	for i in 2:
		player._invincible_timer = 1000.0
		player._fire_timer = 0.0
		player._shoot(Vector2.RIGHT)
		await frames(20)
	expect_events([&"enemy_hit", &"enemy_death"], "shooting a 2-health walker twice")


func test_walker_shot() -> void:
	await reset_scene(true)
	var walker: EnemyWalker = _only("WalkerA")
	walker.global_position = Vector2(250, 153)
	walker.move_speed = 0.0
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(180, 152)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"enemy_shoot"], "a walker firing")
	check("walkers do not use the turret or flyer sound", not events.has(&"turret_shoot") and not events.has(&"flyer_shoot"))


func test_turret_shot_and_prone() -> void:
	await reset_scene(true)
	var turret: EnemyTurret = _only("Turret1")
	turret.global_position = Vector2(500, 153)
	player.global_position = Vector2(430, 152)
	Input.action_press("crouch")
	for i in 60:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"turret_shoot", &"enemy_prone"], "a turret firing at a player who lies down")
	check("enemy_prone is reported once, not every frame", events.count(&"enemy_prone") == 1, str(events.count(&"enemy_prone")))
	check("the turret does not use the walker sound", not events.has(&"enemy_shoot"))
	# set_prone() 是公开方法：对已经趴着的敌人再调一次，不能再报告一遍。
	turret.set_prone(true)
	check("set_prone on an already prone enemy does not report again", events.count(&"enemy_prone") == 1, str(events.count(&"enemy_prone")))


func test_flyer_shot() -> void:
	await reset_scene(true)
	var flyer: EnemyFlyer = _only("FlyerE")
	flyer.set_anchor(Vector2(200, 44))
	flyer.move_speed = 0.0
	player.global_position = Vector2(200, 152)
	for i in 20:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"flyer_shoot"], "E firing down")


func test_chaser_alert() -> void:
	await reset_scene(true)
	var d: EnemyChaser = _only("ChaserD")
	d.global_position = Vector2(250, 153)
	player.global_position = Vector2(560, 152)
	await frames(10)
	check("no alert while D has not seen the player", not events.has(&"chaser_alert"))
	player.global_position = Vector2(180, 152)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	expect_events([&"chaser_alert"], "D spotting the player")
	check("the alert sounds once, not every frame", events.count(&"chaser_alert") == 1, str(events.count(&"chaser_alert")))


# ---------------------------------------------------------------- 播放器与素材包

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
	# 没有备用包、也没提供某个声音：不响、不报错（runner 会把任何 SCRIPT ERROR 记成失败）。
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


func test_sounds_outlive_the_level() -> void:
	# 死亡后关卡会重载；game_over 必须继续响完，所以播放器不能挂在关卡里。
	await reset_scene()
	GameEvents.report(&"game_over")
	free_scene()
	await frames(2)
	check("game_over keeps playing after the level is freed", Sfx.playing_count(&"game_over") >= 1)
	await reset_scene() # 让 runner 收尾时有场景可释放


# ---------------------------------------------------------------- 清单和游戏一致

func test_zz_every_listed_event_happens_in_game() -> void:
	# 排在最后（用例按声明顺序跑）：上面的场景覆盖了清单里的每个事件。
	await reset_scene()
	for event in SkinPack.SOUND_EVENTS:
		check("%s is triggered by gameplay" % event, covered.has(event))
