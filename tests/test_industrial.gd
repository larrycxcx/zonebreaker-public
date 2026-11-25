extends GameTest
## The industrial zone skin pack (stage 2's set, generated from the Industrial Zone Tileset by `tools/terrain_build.py`).
##
## It is **the second zone**, so what it guards differs from the cyberpunk suite: that one guards the nine-slice algorithm and "switching skins does not change the rules",
## this one guards that **"a zone only holds what is unique to it and takes the rest through the fallback" really holds** —
## all 23 stages are set up this way, and if the first zone gets it wrong the other 22 follow.
## Two more came out of this round: do not pick half tiles (thin strips only draw the top half and leave the upper part transparent as a ground top),
## and every backdrop layer must reach the bottom of the view (otherwise the clear colour shows in pits).

const PACK := "res://skins/industrial/industrial_skin.tres"
const CYBERPUNK := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART := "res://skins/industrial"
## View height: the backdrop art is only 324 tall and the build extends it down to here (see BACKDROP_HEIGHT in terrain_build.py).
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

func test_the_pack_brings_its_own_terrain_and_a_backdrop() -> void:
	if needs_art(): return
	# What is unique to a zone is just this: three terrains + this stage's enemies + the backdrop.
	# **Players, bullets, effects and the HUD must not be in its own table at all** — they are shared by all 23 stages, and setting them here would make a copy.
	var mine := pack()
	var keys: Array[String] = []
	for key: StringName in mine.appearances:
		keys.append(String(key))
	keys.sort()
	check("it declares the three terrains, this stage's enemies, its boss, its traps and a ladder",
		keys == ["2_a", "2_b", "2_boss", "2_c", "2_d", "2_e", "2_f", "ladder",
			"terrain_ground", "terrain_ledge", "terrain_stone", "trap_barrel", "trap_crate", "trap_gate", "trap_press"], str(keys))
	check("and a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("industrial"), str(mine.backdrop))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	# **The stage track is unique to this stage**; the boss track and sound effects still come through the fallback
	check("but it brings its own level music", mine.music.has(&"level"), str(mine.music.keys()))


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	if needs_art(): return
	# Characters, bullets, effects, HUD and sounds all have to be available as usual — otherwise stage 2 would be a floor full of placeholder blocks.
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"1_a", &"enemy_bullet", &"1_boss"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null and scene.resource_path.contains("cyberpunk"),
			str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)
	check("and the music", Skins.music(&"level") != null)


func test_the_terrain_art_is_this_zone_and_not_the_last_one() -> void:
	if needs_art(): return
	# A `.tres` alone does not make a new skin: the sprites have to really differ
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		var theirs := (load("res://skins/cyberpunk/terrain/%s.png" % name) as Texture2D).get_image()
		check("%s is its own art" % name, mine.get_data() != theirs.get_data())


# ---------------------------------------------------------------- The two that came out of this round

func test_no_terrain_tile_is_half_empty() -> void:
	if needs_art(): return
	# In the art thin strips (16 tall) and full tiles (32 tall) are mixed, with neighbouring numbers.
	# A thin strip as the ground's top tile leaves its upper half transparent and the ground looks like a row of railings in game — so no image may have a whole empty row.
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
	# The art is only 324 tall, with nothing below the ground line. The stage has pits, where the clear colour would show like a black brick,
	# so the build repeats the bottom row down to the bottom of the view.
	# **Only the rearmost layer has to be opaque**: in this set `sky` stops at the horizon and the `base` haze shows underneath,
	# which is the artist's layering, not a gap — it is the rearmost layer that hides the clear colour.
	for layer: String in ["base", "sky", "far", "mid", "near"]:
		var img := zone_art("backdrop/%s.png" % layer)
		check("%s covers the whole screen" % layer, img.get_height() >= SCREEN_HEIGHT,
			"%dx%d" % [img.get_width(), img.get_height()])
	var back := zone_art("backdrop/base.png")
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
	for p in platforms():
		var visual := p.get_node("Visual")
		check("%s wears terrain art" % p.name, visual is TerrainAppearance, str(visual))
		if visual is TerrainAppearance:
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes it from this zone" % p.name,
				texture != null and texture.resource_path.begins_with(ART), str(texture))


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
	var industrial := await measure(pack())
	check("the player really stands on the ledge and crawls through in this test",
		blocks["on_floor"] and blocks["stands_on_ledge_at"] < 250.0 and blocks["crawled_to"] > 704.0,
		str(blocks))
	for key: String in blocks:
		check("%s is the same in this zone" % key, blocks[key] == industrial[key],
			"blocks %s, industrial %s" % [blocks[key], industrial[key]])


# ---------------------------------------------------------------- This stage's enemies

## This stage's six enemies: skin key → [appearance frame width, frame height, anchor x, anchor y, has feet (the flying one does not)]
const ENEMIES := {
	&"2_a": [80, 56, 40, 40, true],   # Worker: drops from above, charges on landing
	&"2_b": [80, 56, 40, 40, true],   # Heaver: charges
	&"2_c": [80, 56, 40, 40, true],   # Specialist: patrols + shoots + diagonal shots
	&"2_d": [80, 56, 40, 40, true],   # Hammer: walks up and swings a hammer
	&"2_e": [48, 48, 24, 24, false],  # Copter: flies overhead dropping bombs
	&"2_f": [80, 56, 40, 40, true],   # Alarmobot: charges in and blows itself up
}
## The feet land this many pixels below the anchor (the same line as the player and stage 1's enemies).
const FOOT_BELOW_ANCHOR := 16


func sheet(key: StringName, clip: String, side := "r") -> Image:
	return (load("%s/enemies/%s/%s_%s.png" % [ART, key, clip, side]) as Texture2D).get_image()


func has_clip(key: StringName, clip: String) -> bool:
	return ResourceLoader.exists("%s/enemies/%s/%s_r.png" % [ART, key, clip])


func test_every_enemy_the_pack_names_really_has_art() -> void:
	if needs_art(): return
	# If the pack lists a key without sprites, that enemy is an invisible thing in the game — that still shoots you
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
	# Turning around only swaps an image (no flip_h, and certainly no negative scale), so the two must be exact mirrors
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		var anchor: int = spec[2]
		var right := sheet(key, "idle")
		var left := sheet(key, "idle", "l")
		var wrong := 0
		for y in right.get_height():
			for x in right.get_width():
				var frame := x / int(spec[0])
				var within := x % int(spec[0])
				var sx := frame * int(spec[0]) + 2 * anchor - within
				if sx < 0 or sx >= right.get_width() or sx / int(spec[0]) != frame:
					continue
				if right.get_pixel(x, y) != left.get_pixel(sx, y):
					wrong += 1
		check("%s mirrors about its anchor" % key, wrong == 0, "%d pixels do not match" % wrong)


func test_the_ones_that_walk_stand_on_the_same_line() -> void:
	if needs_art(): return
	# Feet 16px below the anchor: the same line as the player and stage 1's enemies, so nobody sinks into the floor or floats when the stage changes
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		if not spec[4]:
			continue
		var img := sheet(key, "idle")
		var lowest := -1
		for y in img.get_height():
			for x in int(spec[0]):
				if img.get_pixel(x, y).a > 0.0:
					lowest = y
					break
		check("%s has its feet on the ground line" % key,
			lowest == int(spec[3]) + FOOT_BELOW_ANCHOR - 1,
			"lowest row y=%d, expected %d" % [lowest, int(spec[3]) + FOOT_BELOW_ANCHOR - 1])


func test_the_one_that_flies_is_centred_on_its_anchor() -> void:
	if needs_art(): return
	# Ground walkers align on the line of their feet; the flyer has no feet — its 28×20 hitbox is **centred on the origin**,
	# so horizontally it has to line up with the anchor column. A few pixels off and the player aiming at the hull would miss.
	var spec: Array = ENEMIES[&"2_e"]
	var img := sheet(&"2_e", "idle")
	var left := int(spec[0])
	var right := -1
	for y in img.get_height():
		for x in int(spec[0]):
			if img.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				right = maxi(right, x)
	var middle := (left + right) / 2.0
	check("2-E's body sits on the anchor column", absf(middle - float(spec[2])) <= 1.0,
		"hull x %d..%d, centre %.1f, anchor %d" % [left, right, middle, spec[2]])


func test_the_ones_that_fight_have_the_frames_their_behaviour_needs() -> void:
	if needs_art(): return
	# Each enemy's attack hinges on a particular frame; with a clip missing from the sprites the behaviour has no picture
	check("2-C has a firing pose", has_clip(&"2_c", "attack_level"))
	check("2-D has the full hammer swing", has_clip(&"2_d", "attack_level")
		and sheet(&"2_d", "attack_level").get_width() / 80 == 8,
		str(sheet(&"2_d", "attack_level").get_width() / 80))
	check("2-E has the bomb drop", has_clip(&"2_e", "attack_down"))
	check("2-F has the siren it flashes before it blows", has_clip(&"2_f", "attack_level"))
	for key: StringName in [&"2_a", &"2_b", &"2_f"]:
		check("%s has a charging pose" % key, has_clip(key, "run"))


# ---------------------------------------------------------------- The two plugged in

func spawn(scene_path: String, at: Vector2) -> Enemy:
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(enemy)
	enemy.global_position = at
	return enemy


func test_the_heaver_charges_like_the_chaser_does() -> void:
	if needs_art(): return
	await reset_scene(false, true, pack())
	var heaver := spawn("res://scenes/enemy_2_b.tscn", Vector2(500, 300))
	player.global_position = Vector2(340, 304)
	snap_camera()
	await frames(4)
	var started: float = heaver.global_position.x
	await frames(40)
	check("it is a chaser", heaver is EnemyChaser)
	check("and it really closes in", heaver.global_position.x < started - 20.0,
		"%.0f -> %.0f" % [started, heaver.global_position.x])
	check("it wears this zone's art", (heaver.get_node("Visual") as Node).get("art_dir") == "%s/enemies/2_b" % ART,
		str((heaver.get_node("Visual") as Node).get("art_dir")))


func test_the_specialist_shoots_and_can_aim_off_the_level() -> void:
	await reset_scene(false, true, pack())
	var spec := spawn("res://scenes/enemy_2_c.tscn", Vector2(500, 300))
	spec.facing = -1
	player.global_position = Vector2(380, 304)
	snap_camera()
	await frames(4)
	check("it never lies down — this pack has no prone art", not spec.can_go_prone)
	check("but it can aim off the level", spec.can_aim_diagonally)
	# The diagonal aim check is a pure function, **so ask it directly**: making the player fly up does not work, gravity pulls them straight back to the ground,
	# the aim becomes level, and this case would turn into "tested a level shot" and still pass.
	var stood := player.global_position
	player.global_position = stood + Vector2(0, -104)
	check("a player up on a ledge is a diagonal target",
		spec.aim_for(player) == Enemy.Aim.DIAGONAL_UP, str(spec.aim_for(player)))
	player.global_position = stood + Vector2(0, 104)
	check("and one down in a pit is the other way",
		spec.aim_for(player) == Enemy.Aim.DIAGONAL_DOWN, str(spec.aim_for(player)))
	player.global_position = stood
	# `shot_fired` has no argument; a lambda with one extra parameter cannot connect (showing up as "not a single shot fired")
	var fired: Array[int] = []
	spec.shot_fired.connect(func() -> void: fired.append(1))
	await frames(180)
	check("and it really fires at the player in front of it", not fired.is_empty(), str(fired.size()))


func test_this_zone_enemies_change_nothing_about_the_rules() -> void:
	# With the sprites changed, the hitbox, patrol and muzzle must not move with them
	var out := []
	for skin: SkinPack in [Skins.default_skin(), pack()]:
		await reset_scene(false, true, skin)
		var spec := spawn("res://scenes/enemy_2_c.tscn", Vector2(500, 300))
		player.global_position = Vector2(-4000, 304)
		snap_camera()
		await frames(4)
		var shape := spec.get_node("CollisionShape2D") as CollisionShape2D
		var walked_from: float = spec.global_position.x
		await frames(90)
		out.append({
			"box": (shape.shape as RectangleShape2D).size,
			"muzzle": spec.level_muzzle_position() - spec.global_position,
			"walked": snappedf(absf(spec.global_position.x - walked_from), 0.5),
		})
	check("it really patrolled in this test", out[0]["walked"] > 20.0, str(out[0]))
	for key: String in out[0]:
		check("%s is the same with either skin" % key, out[0][key] == out[1][key],
			"blocks %s, industrial %s" % [out[0][key], out[1][key]])



# ---------------------------------------------------------------- Four new attacks

## The top of the ground in the level, and the height of the body origin standing on it.
const GROUND_TOP := 320.0
const STAND_Y := GROUND_TOP - 16.0
## The test level's stretch x 1096..1280 **has nothing overhead** (the last platform is at 1000..1096).
## The drop and chase cases are set up here: placed under a platform, a person would land on the platform,
## and a chaser standing on a one-way platform would follow D's "walk off the edge" rule in the opposite direction,
## so the case would see "it runs away from the player".
const OPEN_SKY_X := 1180.0


## Is the enemy gone (`is_alive()` belongs to the player side; dead enemies are simply deleted).
## **The parameter must not be typed**: passing an already freed object into a parameter typed `Node` is an immediate type error.
func gone(enemy: Variant) -> bool:
	return not is_instance_valid(enemy) or (enemy as Node).is_queued_for_deletion()


## Wait for this hammer to swing **from the start**. Waiting directly for `is_swinging()` does not work: it may be midway through a swing,
## and the "wind-up to hit" measured would be only the tail end, with the case falsely reporting "health lost before the hammer hit".
func fresh_swing(hammer: EnemyHammer) -> void:
	hammer._swing_left = 0.0
	hammer._smash_timer = 0.0
	while not hammer.is_swinging():
		await tree.physics_frame


func test_the_worker_hangs_until_someone_walks_under_it() -> void:
	# 2-A is this stage's ambush: hanging above the top of the view, so the player sees nothing on the way in
	await reset_scene(false, true, pack())
	var worker := spawn("res://scenes/enemy_2_a.tscn", Vector2(OPEN_SKY_X, -40)) as EnemyDropper
	player.global_position = Vector2(200, STAND_Y)
	snap_camera()
	var hung := worker.global_position
	await frames(60)
	check("it does not even fall while nobody is near", not worker.has_dropped
		and worker.global_position.is_equal_approx(hung), str(worker.global_position))
	player.global_position = Vector2(worker.global_position.x, STAND_Y)
	snap_camera()
	await frames(4)
	check("walking under it lets it go", worker.has_dropped)
	await frames(90)
	check("and it comes down to the ground", worker.is_on_floor()
		and absf(worker.global_position.y - STAND_Y) < 4.0, str(worker.global_position))
	check("it fell a long way to get there", worker.global_position.y - hung.y > 300.0,
		str(worker.global_position.y - hung.y))


func test_the_worker_lets_go_when_you_shoot_it() -> void:
	# otherwise a player who spotted it could only shoot a target that never fights back
	await reset_scene(false, true, pack())
	var worker := spawn("res://scenes/enemy_2_a.tscn", Vector2(OPEN_SKY_X, -40)) as EnemyDropper
	player.global_position = Vector2(OPEN_SKY_X - 400.0, STAND_Y)
	snap_camera()
	await frames(10)
	check("setup: it is still hanging", not worker.has_dropped)
	worker.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a hit brings it down", worker.has_dropped)


func test_the_worker_charges_once_it_lands() -> void:
	# Once landed it is an ordinary charger (D's behaviour), with no second AI
	await reset_scene(false, true, pack())
	var worker := spawn("res://scenes/enemy_2_a.tscn", Vector2(OPEN_SKY_X, -40)) as EnemyDropper
	player.global_position = Vector2(OPEN_SKY_X - 80.0, STAND_Y)
	snap_camera()
	for i in 120:
		await tree.physics_frame
		if worker.is_on_floor():
			break
	check("setup: it landed", worker.is_on_floor(), str(worker.global_position))
	check("it is a chaser underneath", worker is EnemyChaser)
	# When it lands the player is right at its feet, already caught — move the player away and measure the chase from the start again
	player.global_position = Vector2(OPEN_SKY_X - 200.0, STAND_Y)
	snap_camera()
	await frames(2)
	# It measures "did it close the distance", not "which way it walks": once it touches the player it gets pushed back a bit (D's rule),
	# and if that happens exactly at the moment of sampling it would look like it is walking away
	var gap: float = absf(worker.global_position.x - player.global_position.x)
	var closest := gap
	for i in 60:
		await tree.physics_frame
		closest = minf(closest, absf(worker.global_position.x - player.global_position.x))
	check("and it comes after you", closest < gap - 40.0, "%.0f -> %.0f" % [gap, closest])


func test_the_hammer_only_hurts_you_when_it_lands() -> void:
	# If the player lost health while the hammer was still raised in the picture, they could not tell from the motion when to dodge
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	# Contact damage is a separate mechanism (the base class rule, guarded by other cases), turned off here: both kinds do 42, and mixed together you could not tell which hit
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	await fresh_swing(hammer)
	var before: int = player.health
	check("it winds up first", hammer.is_swinging())
	await frames(int(EnemyHammer.HIT_DELAY * 60.0) - 4)
	check("still nothing while the hammer is in the air", player.health == before,
		"%d -> %d" % [before, player.health])
	await frames(8)
	check("and it lands on you", player.health < before, "%d -> %d" % [before, player.health])


func test_stepping_back_after_the_windup_dodges_the_hammer() -> void:
	# It stands still while swinging, so stepping out of the hammer's reach dodges it
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	# Contact damage is a separate mechanism (the base class rule, guarded by other cases), turned off here: both kinds do 42, and mixed together you could not tell which hit
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	await fresh_swing(hammer)
	var before: int = player.health
	player.global_position = Vector2(200, STAND_Y)
	await frames(int(EnemyHammer.HIT_DELAY * 60.0) + 10)
	check("the hammer comes down on nothing", player.health == before,
		"%d -> %d" % [before, player.health])


func test_the_hammer_never_shoots() -> void:
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	check("it has no gun", hammer.bullet_scene == null)
	hammer.facing = -1
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(150)
	check("and never puts a bullet on the field", bullets(16).is_empty())


func test_the_alarmobot_stops_and_blows_up_next_to_you() -> void:
	# Once lit it stops moving: if it kept chasing, the player could never get away
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(420, STAND_Y)) as EnemyBomber
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("setup: it has not gone off yet", not bot.is_lit() and not gone(bot))
	var before: int = player.health
	for i in 200:
		await tree.physics_frame
		if gone(bot):
			break
	check("it reaches you and goes off", gone(bot))
	check("and the blast hurts", player.health < before, "%d -> %d" % [before, player.health])


func test_running_away_from_a_lit_alarmobot_works() -> void:
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(420, STAND_Y)) as EnemyBomber
	player.global_position = Vector2(390, STAND_Y)
	player.health = 9999
	snap_camera()
	for i in 120:
		await tree.physics_frame
		if bot.is_lit():
			break
	check("setup: the fuse is lit", bot.is_lit())
	var stood: float = bot.global_position.x
	var fuse := bot.fuse_time
	var before: int = player.health
	player.global_position = Vector2(stood - 300.0, STAND_Y)
	# It is gone once the fuse runs out, so "it did not chase you" has to be measured while it is still alive
	var moved := 0.0
	for i in int(fuse * 60.0) - 4:
		await tree.physics_frame
		if gone(bot):
			break
		moved = absf(bot.global_position.x - stood)
	check("it does not chase you once it is lit", moved < 2.0, "%.1f" % moved)
	await frames(30)
	check("it still goes off", gone(bot))
	check("but it goes off on nothing", player.health == before, "%d -> %d" % [before, player.health])


func test_the_copter_drops_bombs_on_what_is_under_it() -> void:
	await reset_scene(false, true, pack())
	var copter := spawn("res://scenes/enemy_2_e.tscn", Vector2(400, 120)) as EnemyCopter
	copter.set_anchor(Vector2(400, 120))
	player.global_position = Vector2(400, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("it has no gun, only bombs", copter.bullet_scene == null and copter.bomb_scene != null)
	var dropped: Array[Node] = []
	for i in 200:
		await tree.physics_frame
		for node in tree.get_nodes_in_group(Grenade.GROUP):
			if not dropped.has(node):
				dropped.append(node)
		if not dropped.is_empty():
			break
	check("it drops one", not dropped.is_empty())
	if dropped.is_empty():
		return
	var bomb := dropped[0] as Grenade
	# **Look at the velocity, not just the position**: at the moment of release the bomb is right under the belly whether it is thrown forward or dropped,
	# and the direction only shows in the velocity (F throws forward, this one lets go straight down)
	check("it is released straight down, not thrown forward",
		absf(bomb.velocity.x) <= 1.0 and bomb.velocity.y > 0.0, str(bomb.velocity))
	check("out of its belly", absf(bomb.global_position.x - copter.global_position.x) <= 2.0
		and bomb.global_position.y > copter.global_position.y,
		str(bomb.global_position - copter.global_position))
	check("and it is the enemies' grenade, so it cannot hurt its own side",
		bomb.target_layer == 2, str(bomb.target_layer))


# ---------------------------------------------------------------- This stage's boss

## The height the boss is placed at in mid-air (it has no gravity and floats there).
const BOSS_Y := 170.0


func spawn_boss() -> BossOperator:
	var boss := (load("res://scenes/boss_2.tscn") as PackedScene).instantiate() as BossOperator
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(OPEN_SKY_X, BOSS_Y)
	boss._home = boss.global_position
	return boss


## Set up the boss and the player and wait for it to appear.
func face_the_operator(player_at: Vector2) -> BossOperator:
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	player.global_position = player_at
	player.health = 9999
	snap_camera()
	await frames(4)
	boss.appear()
	await frames(2)
	return boss


func test_the_operator_is_a_boss_and_shows_up_on_the_hud() -> void:
	if needs_art(): return
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	check("it is a boss", boss is Boss)
	check("it hangs in the air, no gravity", boss.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING)
	check("it brings a portrait from this pack's art",
		boss.hud_portrait() != null
		and boss.hud_portrait().resource_path.begins_with("%s/enemies/2_boss" % ART),
		str(boss.hud_portrait()))
	check("the ultimate only takes a quarter off it",
		boss.ultimate_damage() == roundi(boss.max_health * 0.25), str(boss.ultimate_damage()))


func test_it_drifts_in_eight_directions() -> void:
	# "Flies in eight directions" **asks the direction picker directly** instead of bumping into it in a real run:
	# in five seconds it only picks a direction three or four times, and the chance of all of them being vertical is one in a hundred — the case would fail intermittently,
	# and when it failed it would look like the boss was broken.
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	var seen := {}
	for i in 400:
		boss._pick_heading()
		seen[boss._heading.snapped(Vector2(0.01, 0.01))] = true
	check("all eight headings come up", seen.size() == 8, str(seen.size()))
	var flat := 0
	var slanted := 0
	for heading: Vector2 in seen:
		if is_zero_approx(heading.y):
			flat += 1
		elif not is_zero_approx(heading.x):
			slanted += 1
	check("two of them are straight across", flat == 2, str(flat))
	check("and four are diagonal", slanted == 4, str(slanted))


func test_it_never_leaves_its_own_patch_of_air() -> void:
	# It does not chase — chasing is D's job; this one presses from above, so it must not follow the player out of its ground
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 500.0, STAND_Y))
	var home: Vector2 = boss._home
	var moved := 0.0
	var strayed := Vector2.ZERO
	for i in 300:
		await tree.physics_frame
		var off: Vector2 = boss.global_position - home
		moved = maxf(moved, off.length())
		strayed = Vector2(maxf(strayed.x, absf(off.x) - boss.roam_range.x),
			maxf(strayed.y, absf(off.y) - boss.roam_range.y))
	check("it really moves", moved > 20.0, "%.0f" % moved)
	check("but never leaves its patch", strayed.x < 16.0 and strayed.y < 16.0, str(strayed))


func test_the_arm_only_comes_down_on_someone_underneath() -> void:
	# The cable only drops straight down, so standing below to the side is safe
	var boss := await face_the_operator(Vector2(OPEN_SKY_X + 200.0, STAND_Y))
	# **Pin its drifting**: its horizontal ground is already 200px, and drifting on its own it would end up over this player's head,
	# so this case would test "did it drift over these few seconds" instead of "below to the side is safe".
	boss.roam_range = Vector2.ZERO
	await frames(120)
	check("nobody underneath, so the arm stays in",
		boss.arm_state() == BossOperator.Arm.IN and is_zero_approx(boss.arm_length()),
		"%d / %.0f" % [boss.arm_state(), boss.arm_length()])
	# Move to right below it; pin it vertically too, so it does not drift to a height the cable cannot reach, which is another matter
	boss.roam_range = Vector2.ZERO
	player.global_position = Vector2(boss.global_position.x, STAND_Y)
	var out := false
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		if boss.arm_length() > 0.0:
			out = true
			break
	check("standing under it brings the arm down", out)


func test_the_claw_only_bites_when_it_shuts() -> void:
	# Lowering the cable takes time, during which the player can see it and get away — the same idea as the hammer man
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# Pinned vertically: drifting higher the cable cannot reach, it switches to shooting, and the case would never see the arm
	boss.roam_range.y = 0.0
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		player.health = 9999
		if boss.arm_state() == BossOperator.Arm.OUT:
			break
	check("setup: the arm is on its way down", boss.arm_state() == BossOperator.Arm.OUT)
	var before: int = player.health
	while boss.arm_state() == BossOperator.Arm.OUT:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		check("no bite while the cable is still paying out", player.health == before)
		break
	# Follow it all the way down: health should only be lost the moment the claw closes
	var bitten := false
	for i in 120:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		if player.health < before:
			bitten = boss.arm_state() == BossOperator.Arm.GRAB \
				or boss.arm_state() == BossOperator.Arm.BACK
			break
	check("and it bites when the claw shuts at the bottom", bitten)


func test_stepping_aside_dodges_the_claw() -> void:
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# Pinned vertically: drifting higher the cable cannot reach, it switches to shooting, and the case would never see the arm
	boss.roam_range.y = 0.0
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		if boss.arm_state() == BossOperator.Arm.OUT:
			break
	check("setup: the arm is coming down", boss.arm_state() == BossOperator.Arm.OUT)
	var before: int = player.health
	player.global_position = Vector2(boss.global_position.x - 200.0, STAND_Y)
	for i in 120:
		await tree.physics_frame
		if boss.arm_state() == BossOperator.Arm.IN:
			break
	check("the claw closes on nothing", player.health == before,
		"%d -> %d" % [before, player.health])


func test_the_volley_all_goes_one_way() -> void:
	# The biggest difference from Boss A: that one spreads a fan, this one fires a string of bullets all along one line
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	var shots: Array[Node] = []
	for i in 400:
		await tree.physics_frame
		for b in bullets(16):
			if not shots.has(b):
				shots.append(b)
		if shots.size() >= boss.burst_min:
			break
	check("it puts a volley on the field", shots.size() >= boss.burst_min, str(shots.size()))
	if shots.size() < 2:
		return
	var spread := 0.0
	var first: Vector2 = (shots[0] as Bullet).direction
	for b in shots:
		spread = maxf(spread, rad_to_deg(absf(first.angle_to((b as Bullet).direction))))
	check("every shot in it goes the same way", spread < 1.0, "largest difference %.1f degrees" % spread)
	check("and it is aimed at the player, not straight ahead",
		absf(first.y) > 0.1, str(first))


func test_the_two_attacks_take_turns() -> void:
	# "Alternating two attacks" is this boss's design; with only one the fight would have a single rhythm
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# **Pin it at a height within reach**: drifting up and down on its own, it would get too high for the cable and switch to shooting,
	# and a bug like "it can only use its arm" could slip through — the bullet seen would be forced by being out of reach, not by the rotation.
	boss.roam_range.y = 0.0
	var seen_arm := false
	var seen_volley := false
	for i in 600:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		player.health = 9999
		if boss.arm_length() > 0.0:
			seen_arm = true
		if not bullets(16).is_empty():
			seen_volley = true
		if seen_arm and seen_volley:
			break
	check("it uses the arm", seen_arm)
	check("and the gun", seen_volley)


func test_the_boss_skin_changes_nothing_about_the_rules() -> void:
	var out := []
	for skin: SkinPack in [Skins.default_skin(), pack()]:
		await reset_scene(false, true, skin)
		var boss := spawn_boss()
		boss.appear()
		await frames(2)
		var shape := boss.get_node("CollisionShape2D") as CollisionShape2D
		out.append({
			"box": (shape.shape as RectangleShape2D).size,
			"muzzle": boss._muzzle_position() - boss.global_position,
			"arm_reach": boss.arm_max_length,
			"health": boss.max_health,
		})
	for key: String in out[0]:
		check("%s is the same with either skin" % key, out[0][key] == out[1][key],
			"blocks %s, industrial %s" % [out[0][key], out[1][key]])


func test_it_holds_still_while_the_arm_is_out() -> void:
	# The cable hangs: drifting while lowering would land the claw away from where it aimed,
	# so a player who never moved might be missed, or one standing still might be grabbed. Holding still also makes the attack readable and dodgeable.
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# Pinned vertically: drifting higher the cable cannot reach, it switches to shooting, and the case would never see the arm
	boss.roam_range.y = 0.0
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		player.health = 9999
		if boss.arm_state() == BossOperator.Arm.OUT:
			break
	check("setup: the arm is on its way down", boss.arm_state() == BossOperator.Arm.OUT)
	var anchored: Vector2 = boss.global_position
	var strayed := 0.0
	for i in 200:
		await tree.physics_frame
		player.global_position = Vector2(anchored.x, STAND_Y)
		player.health = 9999
		if boss.arm_state() == BossOperator.Arm.IN:
			break
		strayed = maxf(strayed, boss.global_position.distance_to(anchored))
	check("it stays put from the moment the cable pays out", strayed < 2.0, "%.1f" % strayed)
	check("setup: the arm really finished in this test", boss.arm_state() == BossOperator.Arm.IN)


func test_aiming_off_the_level_falls_back_to_the_art_this_pack_has() -> void:
	if needs_art(): return
	# **This art only draws level shots** (the cyberpunk patroller comes with level / up / down).
	# 2-C still fires diagonally — the rules are unchanged, only the picture still shows the gun held level.
	# Without this fallback, the moment it aimed diagonally it would load a missing image, print a screenful of "Resource file not found",
	# and that frame would vanish from the screen. **This was only found in a screenshot**: not one headless test went red.
	check("setup: this pack really has no diagonal firing art",
		not has_clip(&"2_c", "attack_up") and not has_clip(&"2_c", "attack_down"))
	await reset_scene(false, true, pack())
	var spec := spawn("res://scenes/enemy_2_c.tscn", Vector2(500, STAND_Y))
	var visual: EnemySpriteAppearance = spec.get_node("Visual")
	for aim: Vector2 in [Vector2(1, 0), Vector2(1, -1), Vector2(1, 1)]:
		visual.aim(aim)
		visual.fire()
		var clip := visual.clip()
		check("aiming %s picks a clip this pack actually has" % aim,
			ResourceLoader.exists("%s/enemies/2_c/%s_r.png" % [ART, clip]), String(clip))


func test_the_characters_still_have_faces_in_this_zone() -> void:
	if needs_art(): return
	# **Each stage's pack only holds what is unique to that stage**; the characters are shared by all 23 stages and only exist once, in the pack at the bottom.
	# Portraits were first built from the current pack's folder directly, and returning to the main menu after clearing stage 2 the current pack was the industrial one,
	# which has no character folders, so all three portraits were blank (found in playtesting). Now it follows the fallback chain.
	Skins.use(pack())
	for look: StringName in [&"biker", &"punk", &"cyborg"]:
		var face := UiKit.portrait(look)
		check("%s still has a face here" % look, face != null,
			"the pack found %s" % Skins.file("%s/portrait.png" % look))
	check("and the pack itself really has no character art",
		Skins.file("biker/portrait.png").contains("cyberpunk"),
		Skins.file("biker/portrait.png"))


# ---------------------------------------------------------------- The boss's phase 2

func test_the_operator_turns_nasty_below_half_health() -> void:
	# **Phase 1 only fires one line, which you dodge by stepping aside** — if it never changed after half health, the second half would be a slog (playtest feedback)
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	check("it starts out calm", not boss.is_enraged(), "%d/%d" % [boss.health, boss.max_health])
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("and turns nasty once it is down to half", boss.is_enraged(),
		"%d/%d" % [boss.health, boss.max_health])


func test_it_flies_faster_once_it_is_hurt() -> void:
	var out := []
	for hurt: bool in [false, true]:
		var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
		if hurt:
			boss.take_damage(boss.max_health / 2, Vector2.INF, player)
		# The directions are picked at random, so it compares **the length of the velocity**, not the distance covered
		var fastest := 0.0
		for i in 240:
			await tree.physics_frame
			if boss.arm_state() == BossOperator.Arm.IN:
				fastest = maxf(fastest, boss.velocity.length())
		out.append(fastest)
	check("setup: it really drifts in both runs", out[0] > 1.0, "%.0f" % out[0])
	check("hurt, it moves faster", out[1] > out[0] * 1.2, "%.0f -> %.0f" % [out[0], out[1]])


func test_the_volley_opens_into_a_fan_once_it_is_hurt() -> void:
	# Phase 1 is one line (sidestep), phase 2 a fan (stand in the gap between two shots) — the dodge changes completely
	var spreads := []
	for hurt: bool in [false, true]:
		var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
		if hurt:
			boss.take_damage(boss.max_health / 2, Vector2.INF, player)
		var shots: Array[Node] = []
		for i in 400:
			await tree.physics_frame
			for b in bullets(16):
				if not shots.has(b):
					shots.append(b)
			if shots.size() >= boss.burst_min:
				break
		check("it puts a volley on the field", shots.size() >= 2, str(shots.size()))
		var widest := 0.0
		if shots.size() >= 2:
			var first: Vector2 = (shots[0] as Bullet).direction
			for b in shots:
				widest = maxf(widest, rad_to_deg(absf(first.angle_to((b as Bullet).direction))))
		spreads.append(widest)
	check("calm, every shot goes the same way", spreads[0] < 1.0, "%.1f degrees" % spreads[0])
	check("hurt, the volley opens up", spreads[1] > 10.0, "%.1f degrees" % spreads[1])


func test_the_fan_is_still_dodgeable() -> void:
	# A fan is only "dodgeable" with gaps: the angle between shots must be big enough not to blur into a wall
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	check("the shots are spread wide enough to stand between",
		boss.enrage_fan_spread >= 12.0, str(boss.enrage_fan_spread))
	check("and there are only a few of them", boss.enrage_fan_count <= 3
		and boss.enrage_fan_count >= 2, str(boss.enrage_fan_count))


# ---------------------------------------------------------------- This stage's music

func test_the_zone_has_a_track_of_its_own() -> void:
	if needs_art(): return
	Skins.use(pack())
	var track := Skins.music(&"level")
	check("there is level music", track != null)
	if track == null:
		return
	check("it belongs to this zone", track.resource_path.begins_with(ART), track.resource_path)
	# **Looping tracks must be OGG**: MP3 encoders add a little silence at the start and end, and the seam is audible on every loop
	check("and it is an ogg, so the loop is seamless", track is AudioStreamOggVorbis,
		track.get_class())
	check("the boss track still comes from the pack behind it",
		Skins.music(&"boss") != null and Skins.music(&"boss").resource_path.contains("cyberpunk"),
		str(Skins.music(&"boss")))


func test_each_zone_plays_its_own_music() -> void:
	if needs_art(): return
	# The two zones' stage tracks must really differ — registered wrong, stage 2 would play stage 1's track
	Skins.use(pack())
	var mine := Skins.music(&"level")
	Skins.use(load("res://skins/cyberpunk/cyberpunk_skin.tres") as SkinPack)
	var theirs := Skins.music(&"level")
	check("setup: both zones have one", mine != null and theirs != null)
	check("and they are different tracks", mine != theirs,
		"%s vs %s" % [mine.resource_path if mine else "", theirs.resource_path if theirs else ""])


# ---------------------------------------------------------------- Self-destruct damage

func test_the_alarmobot_blast_falls_off_like_a_grenade() -> void:
	# "The same as a grenade": full damage at the centre, only a graze at the edge — the way to dodge is **to get away**, not to tank it.
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(500, STAND_Y)) as EnemyBomber
	check("it uses the same blast rule as a grenade",
		bot.blast_max_damage > bot.blast_min_damage, "%d / %d"
			% [bot.blast_max_damage, bot.blast_min_damage])
	var centre := Blast.damage_at(0.0, bot.blast_radius, bot.blast_max_damage, bot.blast_min_damage)
	var edge := Blast.damage_at(bot.blast_radius, bot.blast_radius,
		bot.blast_max_damage, bot.blast_min_damage)
	check("dead centre hurts most", centre == bot.blast_max_damage, str(centre))
	check("the edge only grazes", edge == bot.blast_min_damage, str(edge))
	check("and it tails off in between",
		Blast.damage_at(bot.blast_radius / 2.0, bot.blast_radius,
			bot.blast_max_damage, bot.blast_min_damage) < centre)


func test_standing_at_the_edge_of_the_blast_hurts_less_than_hugging_it() -> void:
	# **Both distances must be outside contact range (26px)**: touching it, contact damage is checked every frame,
	# and the blast arrives before the invincibility frames end, measuring 0. It lights its fuse at 36, which is already outside contact range,
	# so in normal play "hugging it hurts less" never happens.
	# **And light the fuse before placing the player**: it charges very fast (220px/s, it closes in within two frames),
	# and placing the player first it would rush in by itself, so both distances would measure the same.
	var taken := []
	for gap: float in [28.0, 54.0]:
		await reset_scene(false, true, pack())
		var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(500, STAND_Y)) as EnemyBomber
		bot.contact_damage = 0
		player.global_position = Vector2(-2000, STAND_Y)     # Send the player away first so it does not charge over
		snap_camera()
		await frames(2)
		bot._light_the_fuse()                                # Once lit it stands still
		var stood: float = bot.global_position.x
		player.global_position = Vector2(stood - gap, STAND_Y)
		player.health = 9999
		snap_camera()
		var before: int = player.health
		for i in 120:
			await tree.physics_frame
			player.global_position = Vector2(stood - gap, STAND_Y)
			if gone(bot):
				break
		taken.append(before - player.health)
	check("setup: both got hit", taken[0] > 0 and taken[1] > 0, str(taken))
	check("close in hurts much more than standing at the edge", taken[0] > taken[1] + 20,
		"near %d, edge %d" % [taken[0], taken[1]])


func test_the_blast_cannot_reach_through_a_wall() -> void:
	# The same as the grenade: shielded by something solid between the centre and the target, it is not hit
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(500, STAND_Y)) as EnemyBomber
	bot.contact_damage = 0
	add_wall(480.0, 56.0)
	player.global_position = Vector2(462, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(2)
	var before: int = player.health
	bot._light_the_fuse()
	for i in 120:
		await tree.physics_frame
		player.global_position = Vector2(462, STAND_Y)
		if gone(bot):
			break
	check("setup: it went off", gone(bot))
	check("but the wall took it", player.health == before, "%d -> %d" % [before, player.health])


# ---------------------------------------------------------------- The hammer charges at you

func test_the_hammer_charges_at_you() -> void:
	# It used to just stroll at patrol speed, and a player standing still was never even hit — no threat at all (2026-09 playtest feedback)
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	hammer.facing = 1                      # Its back to the player: it only counts if it **turns around**
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("it turns to face you", hammer.facing == -1, str(hammer.facing))
	check("and it is charging", hammer.is_charging())
	var gap: float = absf(hammer.global_position.x - player.global_position.x)
	await frames(40)
	var closed: float = absf(hammer.global_position.x - player.global_position.x)
	check("it closes the distance", closed < gap - 40.0, "%.0f -> %.0f" % [gap, closed])


func test_the_charge_is_slower_than_walking_away() -> void:
	# The same idea as D: walking away outpaces it, so it can only push you to fight while backing off — otherwise it would be an impossible-to-shake leech
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	check("charging is faster than patrolling", hammer.charge_speed > hammer.move_speed,
		"%.0f / %.0f" % [hammer.charge_speed, hammer.move_speed])
	check("but slower than the player walks", hammer.charge_speed < player.move_speed,
		"%.0f / %.0f" % [hammer.charge_speed, player.move_speed])


func test_it_does_not_track_you_mid_swing() -> void:
	# If it kept turning to follow you mid-swing, "stepping back after the wind-up dodges it" would be pointless
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	await fresh_swing(hammer)
	check("setup: mid swing", hammer.is_swinging())
	player.global_position = Vector2(700, STAND_Y)     # Get behind it
	await frames(4)
	check("it stops hunting while it swings", not hammer.is_charging())
	check("it does not spin round to follow", hammer.facing == -1, str(hammer.facing))


func test_the_second_phase_announces_itself() -> void:
	# **Without announcing it the player never knows it changed**: flying a bit faster and two extra bullets are not visible enough
	# (the 2026-09 playtest reported "phase 2 never appeared"; it did, it just could not be seen).
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a scratch does not flip it", not boss.is_enraged() and not events.has(&"boss_enrage"))
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("crossing half flips it", boss.is_enraged())
	check("and it says so", events.has(&"boss_enrage"), str(events))
	# **Reported only once**: reporting on every hit would keep the alarm going for the whole second half
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("but only once", not events.has(&"boss_enrage"), str(events))


func test_the_second_phase_shows_up_in_the_arm_too() -> void:
	# **The player usually stands right below it**, where it keeps using the arm — changing only the flying speed and the bullet fan
	# would make phase 2 invisible from the most common spot.
	var slow := 0.0
	var quick := 0.0
	for hurt: bool in [false, true]:
		var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
		boss.contact_damage = 0
		boss.roam_range.y = 0.0
		if hurt:
			boss.take_damage(boss.max_health / 2, Vector2.INF, player)
		# Measure "how many frames the cable takes from starting to drop to the bottom"
		for i in 400:
			await tree.physics_frame
			player.global_position = Vector2(boss.global_position.x, STAND_Y)
			player.health = 9999
			if boss.arm_state() == BossOperator.Arm.OUT:
				break
		var frames_out := 0
		for i in 200:
			await tree.physics_frame
			player.global_position = Vector2(boss.global_position.x, STAND_Y)
			player.health = 9999
			if boss.arm_state() != BossOperator.Arm.OUT:
				break
			frames_out += 1
		if hurt:
			quick = float(frames_out)
		else:
			slow = float(frames_out)
	check("setup: the arm really came down both times", slow > 2.0 and quick > 0.0,
		"%.0f / %.0f" % [slow, quick])
	check("hurt, the claw comes down faster", quick < slow, "%.0f -> %.0f frames" % [slow, quick])


func test_the_hammer_swing_makes_a_noise() -> void:
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	events.clear()
	for i in 180:
		await tree.physics_frame
		player.health = 9999
		if events.has(&"hammer_smash"):
			break
	check("it reports a swing", events.has(&"hammer_smash"), str(events))


func test_a_big_hit_that_jumps_past_half_still_flips_it() -> void:
	# The check is **at or below** half health, not equal: one big hit (grenade, ultimate) can take it from above half
	# straight to below half, and landing exactly on the line is unlikely.
	# With "equal to", nearly every way of fighting would skip right past it and phase 2 would never appear.
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	var half := boss.max_health / 2
	boss.take_damage(boss.max_health - half - SHOT, Vector2.INF, player)   # Hit it down to **above** half health
	await frames(2)
	check("setup: still above half", boss.health > half and not boss.is_enraged(),
		"%d / %d" % [boss.health, half])
	# Cross the line in one hit, not landing exactly on half health
	boss.take_damage(boss.health - half + SHOT * 3, Vector2.INF, player)
	await frames(2)
	check("setup: it landed well below half, not exactly on it",
		boss.health < half and boss.health > 0, "%d / %d" % [boss.health, half])
	check("jumping straight past half still flips it", boss.is_enraged())


func test_landing_exactly_on_half_counts_as_below() -> void:
	# The boundary itself counts too: the hit that lands exactly on half health switches gear, no extra hit needed
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	var half := boss.max_health / 2
	boss.take_damage(boss.max_health - half, Vector2.INF, player)
	await frames(2)
	check("setup: exactly on half", boss.health == half, "%d / %d" % [boss.health, half])
	check("that already counts", boss.is_enraged())
