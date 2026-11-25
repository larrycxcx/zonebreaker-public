extends GameTest
## The cyberpunk skin pack's sounds and music (generated from a CraftPix sound pack by tools/sound_build.py).
##
## What it guards: events with a match use the pack's sounds, those without fall back to the default pack; rapid-fire sounds are short enough (otherwise a burst blurs together),
## the ultimate's freeze sound is no longer than the freeze; the pack has no misspelled event names; music changes by purpose, a stage restart does not start it over,
## a boss appearing switches tracks, the default pack has no music, and music loops.

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
## Events with no match in the pack that fall back to the default pack's 8-bit sounds.
## Nothing in the cyberpunk sound pack matches these, so they fall back to the default pack's 8-bit sounds (the styles mix a little; to be filled in when something suitable turns up).
## The ones missing from the cyberpunk pack that fall back to the default pack's 8-bit sounds (the styles mix a little; to be filled in when something suitable turns up).
## These are missing from the cyberpunk pack and fall back to the default pack's 8-bit placeholder sounds.
## **The last two belong to stage 2** (the hammer swing, the boss switching gear): nothing in that sound pack matches them,
## and stage 2 uses the industrial pack (whose `fallback` chains all the way to the default pack), not this one.
const FROM_DEFAULT := [&"jump", &"stamina_exhausted", &"enemy_prone", &"chaser_alert",
	&"player_down", &"player_revive", &"menu_move", &"menu_select", &"menu_back",
	&"level_clear", &"hammer_smash", &"boss_enrage"]


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func test_sounds_come_from_the_pack_or_fall_back() -> void:
	if needs_art(): return
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
	if needs_art(): return
	for event: StringName in skin().sounds:
		check("%s is a real sound event" % event, SkinPack.SOUND_EVENTS.has(event))


func test_rapid_sounds_are_short() -> void:
	if needs_art(): return
	# Sounds that play several times a second have to be short: the original laser sound is 0.88 seconds and would blur together in rapid fire
	var pack := skin()
	for pair in [[&"player_shoot", 0.25], [&"enemy_shoot", 0.3], [&"turret_shoot", 0.45], [&"flyer_shoot", 0.4],
			[&"bullet_impact", 0.25], [&"grenade_bounce", 0.25], [&"enemy_hit", 0.35]]:
		var length := pack.find_sound(pair[0]).get_length()
		check("%s is short (%.2fs)" % [pair[0], length], length > 0.05 and length <= pair[1])
	var freeze: float = (load("res://scenes/ultimate.tscn") as PackedScene).instantiate().get(&"freeze_time")
	var start := pack.find_sound(&"ultimate_start").get_length()
	check("the ultimate's freeze sound ends with the freeze (%.2fs / %.2fs)" % [start, freeze], start <= freeze + 0.01)


func test_enemies_sound_different_from_the_player() -> void:
	if needs_art(): return
	# The same laser sound, told apart by lowering the pitch: enemies lower than the player, the turret lower still
	var pack := skin()
	var mine := pack.find_sound(&"player_shoot") as AudioStreamWAV
	var theirs := pack.find_sound(&"enemy_shoot") as AudioStreamWAV
	var turret := pack.find_sound(&"turret_shoot") as AudioStreamWAV
	check("enemy shots are lower than the player's", theirs.mix_rate < mine.mix_rate, "%d vs %d" % [theirs.mix_rate, mine.mix_rate])
	check("the turret is lower still", turret.mix_rate < theirs.mix_rate, "%d vs %d" % [turret.mix_rate, theirs.mix_rate])


func test_the_level_plays_its_music_and_keeps_it_across_restarts() -> void:
	if needs_art(): return
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
	if needs_art(): return
	# The stage track is our own and **must be OGG**: MP3 encoders add a little silence at the start and end,
	# and the seam is audible on every loop, while stage music loops all the time.
	# Running tools/sound_build.py would copy the pack's MP3 back over it; this guards against that.
	var track := skin().find_music(&"level")
	check("the level track is there", track != null)
	check("and it is an ogg, which loops seamlessly", track is AudioStreamOggVorbis, track.get_class() if track != null else "null")
	check("about as long as a level loop should be", track != null and track.get_length() > 30.0, "%.0f seconds" % (track.get_length() if track != null else 0.0))


func test_the_boss_brings_its_own_track() -> void:
	if needs_art(): return
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
