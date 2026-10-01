extends GameTest
## 赛博朋克皮肤包的音效和音乐（tools/sound_build.py 从 CraftPix 音效包生成）。
##
## 守的东西：对得上的事件用包里的声音、对不上的回落到默认包；连发的声音够短（不然一串子弹糊成一片）、
## 终极武器定格的声音不超过定格时长；包里没有写错的事件名；音乐按用途换曲、关卡重开不从头放、
## Boss 出场切歌、默认包没有音乐、音乐会循环。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
## 包里对不上、回落到默认包 8-bit 音效的事件。
## 赛博朋克音效包里没有对得上的，回落到默认包的 8-bit 音效（风格会有点混，以后找到合适的再补）。
## 赛博朋克包里没有、回落到默认包 8-bit 音效的那几个（风格会有点混，以后找到合适的再补）。
## 这几个赛博朋克包里没有、回落到默认包的 8-bit 占位音。
## **后两个是第二关的**（抡锤、Boss 换挡）：那套音效包里没有对得上的，
## 而且第二关用的是工业区包（它的 `fallback` 一路串到默认包），不是这个包。
const FROM_DEFAULT := [&"jump", &"stamina_exhausted", &"enemy_prone", &"chaser_alert",
	&"player_down", &"player_revive", &"menu_move", &"menu_select", &"menu_back",
	&"level_clear", &"hammer_smash", &"boss_enrage"]


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func test_sounds_come_from_the_pack_or_fall_back() -> void:
	var pack := skin()
	for event: StringName in SkinPack.SOUND_EVENTS:
		var stream := pack.find_sound(event)
		check("%s has a sound" % event, stream != null)
		if stream == null:
			continue
		if FROM_DEFAULT.has(event):
			check("%s falls back to the default pack" % event, stream.resource_path.begins_with("res://skins/default/"), stream.resource_path)
		else:
			check("%s comes from the cyberpunk pack" % event, stream.resource_path == "res://skins/cyberpunk/sfx/%s.wav" % event, stream.resource_path)


func test_the_pack_only_names_real_events() -> void:
	for event: StringName in skin().sounds:
		check("%s is a real sound event" % event, SkinPack.SOUND_EVENTS.has(event))


func test_rapid_sounds_are_short() -> void:
	# 每秒响好几下的声音得短：原素材的激光声 0.88 秒，连射起来会糊成一片
	var pack := skin()
	for pair in [[&"player_shoot", 0.25], [&"enemy_shoot", 0.3], [&"turret_shoot", 0.45], [&"flyer_shoot", 0.4],
			[&"bullet_impact", 0.25], [&"grenade_bounce", 0.25], [&"enemy_hit", 0.35]]:
		var length := pack.find_sound(pair[0]).get_length()
		check("%s is short (%.2fs)" % [pair[0], length], length > 0.05 and length <= pair[1])
	var freeze: float = (load("res://scenes/ultimate.tscn") as PackedScene).instantiate().get(&"freeze_time")
	var start := pack.find_sound(&"ultimate_start").get_length()
	check("the ultimate's freeze sound ends with the freeze (%.2fs / %.2fs)" % [start, freeze], start <= freeze + 0.01)


func test_enemies_sound_different_from_the_player() -> void:
	# 同一个激光声，靠降调分开：敌人比玩家低、炮台更低
	var pack := skin()
	var mine := pack.find_sound(&"player_shoot") as AudioStreamWAV
	var theirs := pack.find_sound(&"enemy_shoot") as AudioStreamWAV
	var turret := pack.find_sound(&"turret_shoot") as AudioStreamWAV
	check("enemy shots are lower than the player's", theirs.mix_rate < mine.mix_rate, "%d vs %d" % [theirs.mix_rate, mine.mix_rate])
	check("the turret is lower still", turret.mix_rate < theirs.mix_rate, "%d vs %d" % [turret.mix_rate, theirs.mix_rate])


func test_the_level_plays_its_music_and_keeps_it_across_restarts() -> void:
	await reset_scene(false, false, skin())
	check("the level track is on", Music.current == &"level" and Music.playing_stream() == skin().find_music(&"level"),
		"%s / %s" % [Music.current, Music.playing_stream()])
	check("and it loops", Music.playing_stream() != null and Music.playing_stream().get(&"loop") == true)
	var changes := []
	var on_change := func(key: StringName) -> void: changes.append(key)
	Music.track_changed.connect(on_change)
	await reset_scene(false, false, skin())
	Music.track_changed.disconnect(on_change)
	check("restarting the level does not restart the music", changes.is_empty() and Music.current == &"level", str(changes))


func test_the_level_track_is_ours_and_loops_without_a_seam() -> void:
	# 关卡那首是自己做的，**必须是 OGG**：MP3 的编码器会在开头结尾各补一小段静音，
	# 循环转一圈能听见接缝，而关卡音乐是一直循环放的。
	# 跑一遍 tools/sound_build.py 会把素材包里的 MP3 拷回来盖掉它，这条守着别被盖。
	var track := skin().find_music(&"level")
	check("the level track is there", track != null)
	check("and it is an ogg, which loops seamlessly", track is AudioStreamOggVorbis, track.get_class() if track != null else "null")
	check("about as long as a level loop should be", track != null and track.get_length() > 30.0, "%.0f 秒" % (track.get_length() if track != null else 0.0))


func test_the_boss_brings_its_own_track() -> void:
	await reset_scene(true, false, skin())
	keep_only_enemies(["BossMissile"])
	(main.get_node("Enemies/BossMissile") as Boss).appear()
	await frames(1)
	check("the boss switches the music", Music.current == &"boss" and Music.playing_stream() == skin().find_music(&"boss"),
		str(Music.current))
	await reset_scene(false, false, skin())
	check("dying and restarting goes back to the level track", Music.current == &"level" and Music.playing_stream() == skin().find_music(&"level"))


func test_the_default_pack_has_no_music() -> void:
	await reset_scene()
	check("silent with the default pack", Music.playing_stream() == null, str(Music.playing_stream()))
