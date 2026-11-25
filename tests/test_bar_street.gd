extends GameTest
## The bar street skin pack (stage 3's set, generated from the Bar Street Tileset by `tools/terrain_build.py`).
##
## It guards the same things as the industrial zone suite: **a zone only holds what is unique to it and takes the rest through the fallback**,
## tiles not picked as half cells, the backdrop extended to the bottom of the view, switching skins does not change the rules.
## One thing unique to this stage: **this art is "street facades", not a terrain pack** (brick walls, windows, shutters, awnings),
## so the three terrains picked are "brick ground / awning / shutter", not "grass / floating platform / stone block".

const PACK := "res://skins/bar_street/bar_street_skin.tres"
const ART := "res://skins/bar_street"
const SCREEN_HEIGHT := 360


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func zone_art(rel: String) -> Image:
	return (load("%s/%s" % [ART, rel]) as Texture2D).get_image()


func platforms() -> Array[Platform]:
	var out: Array[Platform] = []
	for node in main.get_node("Level").find_children("*", "Platform", true, false):
		out.append(node as Platform)
	return out


# ---------------------------------------------------------------- Only what is unique to it

func test_the_pack_brings_terrain_a_backdrop_and_its_own_track() -> void:
	if needs_art(): return
	var mine := pack()
	var keys: Array[String] = []
	for key: StringName in mine.appearances:
		keys.append(String(key))
	keys.sort()
	check("it declares the three terrains, this stage's enemies and its boss",
		keys == ["3_a", "3_b", "3_boss", "3_c", "3_d", "3_e", "3_f",
			"terrain_ground", "terrain_ledge", "terrain_stone"], str(keys))
	check("and a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("bar_street"), str(mine.backdrop))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	check("but it brings its own level music", mine.music.has(&"level"), str(mine.music.keys()))


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	if needs_art(): return
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"enemy_bullet", &"player_grenade"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null and scene.resource_path.contains("cyberpunk"),
			str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)


func test_the_track_is_this_zone_and_loops_cleanly() -> void:
	if needs_art(): return
	Skins.use(pack())
	var track := Skins.music(&"level")
	check("there is level music", track != null)
	if track == null:
		return
	check("it belongs to this zone", track.resource_path.begins_with(ART), track.resource_path)
	# **Looping tracks must be OGG**: MP3 encoders add a little silence at the start and end, and the seam is audible on every loop
	check("and it is an ogg", track is AudioStreamOggVorbis, track.get_class())


func test_each_zone_plays_its_own_track() -> void:
	if needs_art(): return
	var heard := {}
	for path: String in [PACK, "res://skins/industrial/industrial_skin.tres",
			"res://skins/cyberpunk/cyberpunk_skin.tres"]:
		Skins.use(load(path) as SkinPack)
		var track := Skins.music(&"level")
		check("%s has level music" % path.get_file(), track != null)
		if track != null:
			heard[track.resource_path] = true
	check("three zones, three different tracks", heard.size() == 3, str(heard.keys()))


# ---------------------------------------------------------------- Are the tiles picked right

func test_the_terrain_art_is_this_zone_and_not_another() -> void:
	if needs_art(): return
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		for other: String in ["cyberpunk", "industrial"]:
			var theirs := (load("res://skins/%s/terrain/%s.png" % [other, name]) as Texture2D).get_image()
			check("%s is not %s's" % [name, other], mine.get_data() != theirs.get_data())


func test_no_terrain_tile_is_half_empty() -> void:
	if needs_art(): return
	# In this set the 16-tall thin strips (awnings) are mixed with the full tiles. Using a thin strip as the ground's top tile leaves its upper half transparent.
	for name: String in ["ground", "ledge", "stone"]:
		var img := zone_art("terrain/%s.png" % name)
		var empty := 0
		for y in img.get_height():
			var blank := true
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					blank = false
					break
			if blank:
				empty += 1
		check("%s has no blank rows" % name, empty == 0, "%d rows are empty (%dx%d)"
			% [empty, img.get_width(), img.get_height()])


func test_the_backdrop_reaches_the_bottom_of_the_screen() -> void:
	if needs_art(): return
	# The art is only 324 tall and the stages have pits, which would show the clear colour — the build extends it down to the bottom of the view.
	for layer: String in ["sky", "far", "mid", "near", "street"]:
		var img := zone_art("backdrop/%s.png" % layer)
		check("%s covers the whole screen" % layer, img.get_height() >= SCREEN_HEIGHT,
			"%dx%d" % [img.get_width(), img.get_height()])
	var back := zone_art("backdrop/sky.png")
	var gaps := 0
	for x in back.get_width():
		if back.get_pixel(x, SCREEN_HEIGHT - 1).a < 1.0:
			gaps += 1
	check("the backmost layer is solid along the bottom row, so pits never show the clear colour",
		gaps == 0, "%d columns are see-through" % gaps)


# ---------------------------------------------------------------- Once plugged in

func test_every_platform_wears_this_zone_terrain() -> void:
	if needs_art(): return
	await reset_scene(true, true, pack())
	var checked := 0
	for p in platforms():
		var visual := p.get_node("Visual")
		check("%s wears terrain art" % p.name, visual is TerrainAppearance, str(visual))
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes it from this zone" % p.name,
				texture != null and texture.resource_path.begins_with(ART), str(texture))
	check("setup: the terrain is skinned at all", checked > 5, str(checked))


func test_the_backdrop_goes_in_behind_everything() -> void:
	if needs_art(): return
	await reset_scene(true, true, pack())
	var backdrop := main.get_node_or_null("Backdrop")
	check("the level gets a backdrop", backdrop != null)
	if backdrop == null:
		return
	check("drawn first, behind everything", backdrop.get_index() == 0, str(backdrop.get_index()))
	check("it has parallax layers", backdrop.find_children("*", "Parallax2D", true, false).size() == 5)
	check("and no collision at all",
		backdrop.find_children("*", "CollisionObject2D", true, false).is_empty()
		and backdrop.find_children("*", "CollisionShape2D", true, false).is_empty())


# ---------------------------------------------------------------- Switching skins does not change the rules

func measure(skin: SkinPack) -> Dictionary:
	await reset_scene(false, true, skin)
	var out := {}
	var shapes := []
	for p in platforms():
		var shape := p.get_node("CollisionShape2D") as CollisionShape2D
		shapes.append([String(p.name), p.global_position + shape.position,
			(shape.shape as RectangleShape2D).size, shape.one_way_collision])
	out["platforms"] = str(shapes)
	player.global_position = Vector2(208, 200)
	player.velocity = Vector2.ZERO
	await frames(40)
	out["stands_on_ledge_at"] = snappedf(player.global_position.y, 0.01)
	out["on_floor"] = player.is_on_floor()
	player.global_position = Vector2(560, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	Input.action_press("crouch")
	Input.action_press("move_right")
	await frames(150)
	release_all_input()
	out["crawled_to"] = snappedf(player.global_position.x, 1.0)
	return out


func test_this_zone_changes_nothing_about_the_rules() -> void:
	var blocks := await measure(Skins.default_skin())
	var street := await measure(pack())
	check("the player really stands on the ledge and crawls through in this test",
		blocks["on_floor"] and blocks["stands_on_ledge_at"] < 250.0 and blocks["crawled_to"] > 704.0,
		str(blocks))
	for key: String in blocks:
		check("%s is the same in this zone" % key, blocks[key] == street[key],
			"blocks %s, bar street %s" % [blocks[key], street[key]])


# ---------------------------------------------------------------- This stage's enemies

## Skin key → [frame width, frame height, anchor x, anchor y]. **3-E's anchor is moved down**:
## lying on the ground it is only 11px tall with a 28×12 hitbox, and without moving the anchor its sprite would sink into the floor.
const ENEMIES := {
	&"3_a": [80, 56, 40, 40],   # knifeman: winds up, then lunges to stab
	&"3_b": [80, 56, 40, 40],   # gunman: patrols + shoots + real diagonal shots
	&"3_c": [80, 56, 40, 40],   # swordsman: leaps at the player, slashes on landing
	&"3_d": [80, 56, 40, 40],   # brute: soaks damage from the front, does not charge
	&"3_e": [80, 56, 40, 49],   # shark bot: fixed to the floor, shoots along the floor
	&"3_f": [80, 56, 40, 40],   # cannon cart: a slow-moving turret
}
const STAND_Y := 304.0


func sheet(key: StringName, clip: String, side := "r") -> Image:
	return (load("%s/enemies/%s/%s_%s.png" % [ART, key, clip, side]) as Texture2D).get_image()


func has_clip(key: StringName, clip: String) -> bool:
	return ResourceLoader.exists("%s/enemies/%s/%s_r.png" % [ART, key, clip])


func spawn(scene_path: String, at: Vector2) -> Enemy:
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(enemy)
	enemy.global_position = at
	return enemy


func test_every_enemy_the_pack_names_really_has_art() -> void:
	if needs_art(): return
	var mine := pack()
	for key: StringName in ENEMIES:
		var scene := mine.appearances.get(key) as PackedScene
		check("%s is registered" % key, scene != null)
		check("%s has an idle, a hurt and a death" % key,
			has_clip(key, "idle") and has_clip(key, "hurt") and has_clip(key, "death"))
		var spec: Array = ENEMIES[key]
		var img := sheet(key, "idle")
		check("%s draws at %dx%d" % [key, spec[0], spec[1]],
			img.get_height() == spec[1] and img.get_width() % spec[0] == 0,
			"%dx%d" % [img.get_width(), img.get_height()])


func test_the_art_is_mirrored_left_and_right() -> void:
	if needs_art(): return
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		var right := sheet(key, "idle")
		var left := sheet(key, "idle", "l")
		var wrong := 0
		for y in right.get_height():
			for x in right.get_width():
				var frame := x / int(spec[0])
				var within := x % int(spec[0])
				var sx := frame * int(spec[0]) + 2 * int(spec[2]) - within
				if sx < 0 or sx >= right.get_width() or sx / int(spec[0]) != frame:
					continue
				if right.get_pixel(x, y) != left.get_pixel(sx, y):
					wrong += 1
		check("%s mirrors about its anchor" % key, wrong == 0, "%d pixels do not match" % wrong)


func test_everyone_stands_on_the_same_line() -> void:
	if needs_art(): return
	# Feet land 16px below the anchor (the build script's convention). **3-E's anchor is different**:
	# its sprite still has the feet on the bottom edge of the frame; only the appearance scene moved the anchor down to match the short hitbox.
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		var img := sheet(key, "idle")
		var lowest := -1
		for y in img.get_height():
			for x in int(spec[0]):
				if img.get_pixel(x, y).a > 0.0:
					lowest = y
					break
		check("%s has its feet on the generator's ground line" % key, lowest == 40 + 16 - 1,
			"lowest row y=%d" % lowest)


func test_the_gunman_brings_real_diagonal_art() -> void:
	if needs_art(): return
	# **This is exactly what stage 2's 2-C lacks**: that art only draws level shots, so diagonal shots show the gun held level.
	# This stage's gunman comes with three angles, so the rules and the picture finally agree.
	check("it has a level firing pose", has_clip(&"3_b", "attack_level"))
	check("and one for aiming up", has_clip(&"3_b", "attack_up"))
	check("and one for aiming down", has_clip(&"3_b", "attack_down"))
	# The three sets must really differ (copying the same one would mean drawing nothing)
	var level := sheet(&"3_b", "attack_level").get_data()
	check("the three are really different poses",
		sheet(&"3_b", "attack_up").get_data() != level
		and sheet(&"3_b", "attack_down").get_data() != level)


func test_the_ones_that_fight_have_the_frames_their_behaviour_needs() -> void:
	if needs_art(): return
	check("3-A has a charging pose for its lunge", has_clip(&"3_a", "run"))
	check("3-C has an airborne pose for its leap", has_clip(&"3_c", "air"))
	check("3-E has a firing pose", has_clip(&"3_e", "attack_level"))
	check("but no walk — it is bolted to the ground", not has_clip(&"3_e", "walk"))
	check("3-F has a firing pose", has_clip(&"3_f", "attack_level"))


# ---------------------------------------------------------------- The three plugged in

func test_the_gunman_patrols_and_shoots_off_the_level() -> void:
	await reset_scene(false, true, pack())
	var gun := spawn("res://scenes/enemy_3_b.tscn", Vector2(500, STAND_Y))
	gun.facing = -1
	player.global_position = Vector2(380, STAND_Y)
	snap_camera()
	await frames(4)
	check("it can aim off the level", gun.can_aim_diagonally)
	var stood := player.global_position
	player.global_position = stood + Vector2(0, -104)
	check("a player up on a ledge is a diagonal target",
		gun.aim_for(player) == Enemy.Aim.DIAGONAL_UP, str(gun.aim_for(player)))
	player.global_position = stood
	var fired: Array[int] = []
	gun.shot_fired.connect(func() -> void: fired.append(1))
	await frames(180)
	check("and it really fires", not fired.is_empty(), str(fired.size()))


func test_the_cannon_lobs_grenades_instead_of_shooting() -> void:
	# Changed after a 2026-10 playtest: it used to be a turret firing bursts, now it **fires grenades from its barrel** —
	# the whole thing is stage 1 F's "grenades only" behaviour (`EnemyGrenadier`), just moving slowly with the release point at the barrel's mouth.
	await reset_scene(false, true, pack())
	var cannon := spawn("res://scenes/enemy_3_f.tscn", Vector2(500, STAND_Y)) as EnemyGrenadier
	check("it is a grenadier", cannon != null)
	if cannon == null:
		return
	check("it moves, but slowly", cannon.move_speed > 0.0 and cannon.move_speed < 60.0,
		str(cannon.move_speed))
	check("it carries no gun", cannon.bullet_scene == null)
	check("it loads enemy grenades (they only hurt players)", cannon.grenade_scene != null
		and cannon.grenade_scene.resource_path == "res://scenes/enemy_grenade.tscn",
		str(cannon.grenade_scene))
	# The barrel mouth is measured from the art (it was the muzzle position when it used to shoot); F's is where the bat swing arcs
	check("they leave from the barrel, not from F's bat swing",
		cannon.throw_offset == Vector2(18, -9), str(cannon.throw_offset))
	cannon.facing = 1
	player.global_position = Vector2(700, STAND_Y)
	snap_camera()
	var thrown: Array[Node2D] = []
	var shots: Array[int] = []
	cannon.shot_fired.connect(func() -> void: shots.append(1))
	# `launch_projectile()` positions the node **after** adding it to the tree, so only remember the node and look where it is a frame later
	var watch := func(node: Node) -> void:
		if node is Grenade:
			thrown.append(node as Node2D)
	tree.node_added.connect(watch)
	var first_seen := Vector2.INF
	for i in 150:
		await tree.physics_frame
		if first_seen == Vector2.INF and not thrown.is_empty() and is_instance_valid(thrown[0]):
			first_seen = thrown[0].global_position
	tree.node_added.disconnect(watch)
	check("it really lobs them at a player in front", thrown.size() >= 1, str(thrown.size()))
	check("and never fires a bullet", shots.is_empty(), str(shots.size()))
	check("the grenade comes out ahead of the barrel, towards the player",
		first_seen != Vector2.INF and first_seen.x > cannon.global_position.x + 10.0,
		"%s vs cannon at %s" % [first_seen, cannon.global_position])


func test_the_shark_is_bolted_down_and_fires_along_the_floor() -> void:
	# **This stage's new rule**: existing enemies fire standing, with bullets 21~25 above the floor, and lying prone dodges them.
	# This one fires along the floor: **lying prone does not dodge it, only jumping over does** — exactly the other way round.
	await reset_scene(false, true, pack())
	var shark := spawn("res://scenes/enemy_3_e.tscn", Vector2(500, STAND_Y)) as Enemy
	await frames(4)
	var box := shark.get_node("CollisionShape2D") as CollisionShape2D
	var size := (box.shape as RectangleShape2D).size
	check("it is a low thing", size.y <= 16.0, str(size))
	check("it never walks", not (shark is EnemyWalker))
	var floor_y: float = shark.global_position.y + size.y / 2.0
	var muzzle: float = shark.level_muzzle_position().y
	check("and its gun hugs the floor", floor_y - muzzle < Player.CROUCH_HEIGHT,
		"above floor %.0f, prone height %.0f" % [floor_y - muzzle, Player.CROUCH_HEIGHT])


func test_crouching_does_not_dodge_the_shark() -> void:
	await reset_scene(false, true, pack())
	var shark := spawn("res://scenes/enemy_3_e.tscn", Vector2(560, STAND_Y))
	shark.contact_damage = 0
	player.global_position = Vector2(360, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	Input.action_press("crouch")
	await frames(10)
	check("setup: the player really is prone", player.is_crouching)
	var before: int = player.health
	for i in 240:
		await tree.physics_frame
		if player.health < before:
			break
	release_all_input()
	check("ducking under it does not work", player.health < before,
		"%d -> %d" % [before, player.health])


# ---------------------------------------------------------------- Three new attacks

func test_the_knifeman_winds_up_before_it_lunges() -> void:
	# **The wind-up is the player's window**: the lunge is much faster than the player's walk (180), so running does not work,
	# only jumping away in the fraction of a second it freezes. Without that warning it would be undodgeable.
	await reset_scene(false, true, pack())
	var knife := spawn("res://scenes/enemy_3_a.tscn", Vector2(500, STAND_Y)) as EnemyLunger
	knife.facing = -1
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("it is faster than the player can walk", knife.lunge_speed > player.move_speed,
		"%.0f / %.0f" % [knife.lunge_speed, player.move_speed])
	var winding := false
	var dashing := false
	for i in 120:
		await tree.physics_frame
		if knife.is_winding_up():
			winding = true
			check("it holds still while winding up", absf(knife.velocity.x) < 1.0,
				"%.1f" % knife.velocity.x)
		if knife.is_dashing():
			dashing = true
			break
	check("it winds up first", winding)
	check("then it goes", dashing)


func test_the_lunge_commits_to_one_direction() -> void:
	# After starting it lunges in that direction without turning to follow — if it followed, "jumping away dodges it" would be pointless
	await reset_scene(false, true, pack())
	var knife := spawn("res://scenes/enemy_3_a.tscn", Vector2(500, STAND_Y)) as EnemyLunger
	knife.facing = -1
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	for i in 120:
		await tree.physics_frame
		if knife.is_winding_up():
			break
	check("setup: winding up, facing the player", knife.is_winding_up() and knife.facing == -1)
	player.global_position = Vector2(700, STAND_Y)      # Get behind it
	await frames(10)
	check("it still goes the way it committed to", knife.facing == -1, str(knife.facing))


func test_the_swordsman_leaps_over_things() -> void:
	# It is the only enemy in this stage that actively crosses terrain — low walls do not stop it, so hiding behind cover and chipping away does not work on it
	await reset_scene(false, true, pack())
	var sword := spawn("res://scenes/enemy_3_c.tscn", Vector2(500, STAND_Y)) as EnemyLeaper
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	for i in 200:
		await tree.physics_frame
		if sword.is_leaping():
			break
	check("it leaps", sword.is_leaping())
	# **Measure the height after take-off**: the loop above exits on the very frame it becomes "airborne", before it has risen
	var highest: float = sword.global_position.y
	for i in 60:
		await tree.physics_frame
		highest = minf(highest, sword.global_position.y)
	check("and really gets off the ground", STAND_Y - highest > 20.0,
		"%.0f" % (STAND_Y - highest))


func test_stepping_aside_dodges_the_landing_slash() -> void:
	# The landing spot is fixed the moment it jumps; one step aside and the slash misses
	await reset_scene(false, true, pack())
	var sword := spawn("res://scenes/enemy_3_c.tscn", Vector2(500, STAND_Y)) as EnemyLeaper
	sword.contact_damage = 0
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	for i in 200:
		await tree.physics_frame
		if sword.is_leaping():
			break
	check("setup: it is in the air", sword.is_leaping())
	var before: int = player.health
	# **Run to the other side, but stay within its reach**: run too far and it would not turn around even if it could,
	# and this case would test nothing (the first version went to 820, beyond `leap_range`).
	var behind: float = sword.global_position.x + 90.0
	for i in 120:
		await tree.physics_frame
		player.global_position = Vector2(behind, STAND_Y)
		player.health = 9999 if player.health > before else player.health
		if not sword.is_leaping():
			break
	check("it does not turn round in mid air", sword.facing == -1, str(sword.facing))
	check("the slash lands on nothing", player.health == before,
		"%d -> %d" % [before, player.health])


func test_the_brute_shrugs_off_shots_from_the_front() -> void:
	# Breastplate and pauldrons are in front: **hits from the front do half damage, hits from behind full damage**.
	# It forces you to get behind it, jump over it, or lob a grenade over its head (the arc lands behind it).
	await reset_scene(false, true, pack())
	var brute := spawn("res://scenes/enemy_3_d.tscn", Vector2(500, STAND_Y)) as EnemyBrute
	await frames(2)
	check("it really has armour", brute.front_armour < 1.0, str(brute.front_armour))
	# **The facing has to be fixed at the moment of the hit**: it turns to walk toward the player, so after one `await` the facing has changed,
	# and the "front" hit becomes a hit from behind — which is how the first version measured it backwards.
	player.global_position = Vector2(-4000, STAND_Y)
	brute.facing = 1
	var full: int = brute.health
	brute.take_damage(40, Vector2(600, STAND_Y), player)        # It faces right: this is the front
	var from_front: int = full - brute.health
	brute.health = full
	brute.take_damage(40, Vector2(400, STAND_Y), player)        # From behind
	var from_behind: int = full - brute.health
	check("a shot from the front is blunted", from_front < from_behind,
		"front %d, back %d" % [from_front, from_behind])
	check("and from behind it lands in full", from_behind == 40, str(from_behind))
	check("the front hit matches the armour",
		from_front == maxi(1, roundi(40 * brute.front_armour)), str(from_front))


func test_the_brute_does_not_charge() -> void:
	# As promised, "no charging": it is just a wall slowly pressing in, and positioning is entirely up to the player
	await reset_scene(false, true, pack())
	var brute := spawn("res://scenes/enemy_3_d.tscn", Vector2(500, STAND_Y)) as EnemyBrute
	check("it never moves faster than it walks", brute.charge_speed <= brute.move_speed,
		"%.0f / %.0f" % [brute.charge_speed, brute.move_speed])
	check("but it is slower than the player", brute.move_speed < player.move_speed,
		"%.0f / %.0f" % [brute.move_speed, player.move_speed])
	brute.facing = 1
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	check("and it still turns to come at you", brute.facing == -1, str(brute.facing))


func test_armour_does_not_apply_to_damage_with_no_direction() -> void:
	# Unknown sources (damage over time, falling out of the stage) are not reduced — the armour stops things that hit it, not all damage
	await reset_scene(false, true, pack())
	var brute := spawn("res://scenes/enemy_3_d.tscn", Vector2(500, STAND_Y)) as EnemyBrute
	await frames(2)
	player.global_position = Vector2(-4000, STAND_Y)
	brute.facing = 1
	var full: int = brute.health
	brute.take_damage(40)
	check("an undirected hit lands in full", full - brute.health == 40, str(full - brute.health))


# ---------------------------------------------------------------- This stage's boss

func spawn_boss() -> BossWheel:
	var boss := (load("res://scenes/boss_3.tscn") as PackedScene).instantiate() as BossWheel
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(900, STAND_Y - 12.0)
	boss._home = boss.global_position
	return boss


## Place the boss and the player. **The walls have to go** (second argument false): the test level's wall at x=800 sits right between it and the player,
## and it **stands on the ground** — its sight comes from its body centre and is blocked by the wall, `find_target()` stays null,
## and it does nothing. The previous two bosses either fly or are tall, their rays passing over the wall, so they never ran into this.
func face_the_mech(player_at: Vector2) -> BossWheel:
	await reset_scene(false, false, pack())
	var boss := spawn_boss()
	player.global_position = player_at
	player.health = 99999
	snap_camera()
	await frames(4)
	boss.appear()
	await frames(2)
	return boss


func test_the_mech_is_a_boss_and_stands_on_the_ground() -> void:
	if needs_art(): return
	await reset_scene(false, false, pack())
	var boss := spawn_boss()
	check("it is a boss", boss is Boss)
	# **Of the previous two bosses one flew and one walked; this one is heavy ground armour**: it rolls on a single wheel and feels gravity
	check("it is not a floating one", boss.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	check("it brings a portrait from this pack's art",
		boss.hud_portrait() != null
		and boss.hud_portrait().resource_path.begins_with("%s/enemies/3_boss" % ART),
		str(boss.hud_portrait()))
	check("the ultimate only takes a quarter off it",
		boss.ultimate_damage() == roundi(boss.max_health * 0.25), str(boss.ultimate_damage()))


func test_its_three_moves_come_round_in_turn() -> void:
	# **Three moves in rotation, not picked at random**: two rounds and you know the rhythm, and when you die you know what went wrong.
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	var seen: Array[int] = []
	for i in 900:
		await tree.physics_frame
		player.global_position = Vector2(640, STAND_Y)
		player.health = 99999
		var now := boss.move_kind()
		if (now == BossWheel.Move.SHOOT or now == BossWheel.Move.LOB
				or now == BossWheel.Move.WINDUP) and (seen.is_empty() or seen[-1] != now):
			seen.append(now)
		if seen.size() >= 4:
			break
	check("it uses the cannon", seen.has(BossWheel.Move.SHOOT), str(seen))
	check("and the lob", seen.has(BossWheel.Move.LOB), str(seen))
	check("and the roll", seen.has(BossWheel.Move.WINDUP), str(seen))
	check("and it never does the same one twice in a row",
		seen.size() < 2 or seen[0] != seen[1], str(seen))


func test_the_roll_is_telegraphed() -> void:
	# The wind-up is the player's window to jump away. Without a warning it would be undodgeable.
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	check("there really is a wind-up", boss.roll_windup > 0.2, str(boss.roll_windup))
	var held := true
	var rolled := false
	for i in 900:
		await tree.physics_frame
		player.global_position = Vector2(640, STAND_Y)
		player.health = 99999
		if boss.move_kind() == BossWheel.Move.WINDUP:
			held = held and absf(boss.velocity.x) < 1.0
		if boss.move_kind() == BossWheel.Move.ROLL:
			rolled = true
			break
	check("it holds still while winding up", held)
	check("then it rolls", rolled)
	check("and the roll is faster than it patrols", boss.roll_speed > boss.roam_speed,
		"%.0f / %.0f" % [boss.roll_speed, boss.roam_speed])


func test_the_lob_arcs_over_cover() -> void:
	# **This move is the answer to "chipping away from behind a platform"**: the bomb flies in an arc and clears cover.
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	var thrown: Array[Node] = []
	for i in 900:
		await tree.physics_frame
		player.global_position = Vector2(640, STAND_Y)
		player.health = 99999
		for node in tree.get_nodes_in_group(Grenade.GROUP):
			if not thrown.has(node):
				thrown.append(node)
		if not thrown.is_empty():
			break
	check("it lobs something", not thrown.is_empty())
	if thrown.is_empty():
		return
	var bomb := thrown[0] as Grenade
	# An arc: it leaves angled upward, not flying straight
	check("and it really arcs, not flies straight", bomb.velocity.y < 0.0, str(bomb.velocity))
	check("towards the player", signf(bomb.velocity.x) == signf(640.0 - boss.global_position.x),
		str(bomb.velocity))
	check("and it is the enemies' bomb, so it cannot hurt its own side",
		bomb.target_layer == 2, str(bomb.target_layer))


func test_it_never_leaves_its_patch() -> void:
	# It does not chase out of its ground — positioning is the player's job (same idea as the previous two bosses).
	# **Asserting only "it never left its own `roam_range`" is not enough**: raise that number and it naturally never leaves, which tests nothing.
	# What has to be tested is "it does not press all the way toward the player".
	var boss := await face_the_mech(Vector2(200, STAND_Y))
	var home: Vector2 = boss._home
	var strayed := 0.0
	var closest := absf(boss.global_position.x - 200.0)
	for i in 400:
		await tree.physics_frame
		player.global_position = Vector2(200, STAND_Y)
		player.health = 99999
		strayed = maxf(strayed, absf(boss.global_position.x - home.x) - boss.roam_range)
		closest = minf(closest, absf(boss.global_position.x - 200.0))
	check("it stays in its patch", strayed < 40.0, "%.0f" % strayed)
	check("and never comes over to get you", closest > 300.0, "closest %.0f" % closest)
	# **Its ground has to fit inside the boss area**: it wanders `roam_range` each way, and the whole thing must not exceed one screen,
	# or the platforms the stage gives it would not reach it (this constraint comes from the level design, not from the boss).
	check("and its patch fits on one screen", boss.roam_range * 2.0 <= 640.0,
		str(boss.roam_range))


func test_it_turns_nasty_below_half_and_says_so() -> void:
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a scratch does not flip it", not boss.is_enraged() and not events.has(&"boss_enrage"))
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("crossing half flips it", boss.is_enraged())
	check("and it says so", events.has(&"boss_enrage"), str(events))
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("but only once", not events.has(&"boss_enrage"), str(events))


func test_hurt_it_rolls_faster_and_rests_less() -> void:
	await reset_scene(false, false, pack())
	var boss := spawn_boss()
	var calm_roll: float = boss._speed(boss.roll_speed)
	var calm_rest: float = boss._timing(boss.attack_rest)
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("setup: it is enraged", boss.is_enraged())
	check("it rolls faster", boss._speed(boss.roll_speed) > calm_roll,
		"%.0f -> %.0f" % [calm_roll, boss._speed(boss.roll_speed)])
	check("and pauses less between moves", boss._timing(boss.attack_rest) < calm_rest,
		"%.2f -> %.2f" % [calm_rest, boss._timing(boss.attack_rest)])


func test_the_boss_skin_changes_nothing_about_the_rules() -> void:
	var out := []
	for skin: SkinPack in [Skins.default_skin(), pack()]:
		await reset_scene(false, false, skin)
		var boss := spawn_boss()
		boss.appear()
		await frames(2)
		var shape := boss.get_node("CollisionShape2D") as CollisionShape2D
		out.append({
			"box": (shape.shape as RectangleShape2D).size,
			"muzzle": boss._muzzle_position() - boss.global_position,
			"health": boss.max_health,
			"roam": boss.roam_range,
		})
	for key: String in out[0]:
		check("%s is the same with either skin" % key, out[0][key] == out[1][key],
			"blocks %s, bar street %s" % [out[0][key], out[1][key]])
