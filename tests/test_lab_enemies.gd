extends GameTest
## The lab's (stage 5's) enemies. Their attacks were agreed with the user in 2026-11:
##
## | Key | Art | Attack | Implementation |
## |---|---|---|---|
## | 5_a | scientist (black hair) | patrols, throws acid flasks; **turns into a mutant** when hit without dying or approached | `EnemyScientist` (F's grenade throwing + transforming) |
## | 5_b | scientist (grey hair) | transforms as soon as it sees the player (the transformation is an opening) | as above, `transform_on_sight` |
## | 5_c | mutant | walks up, raises its fists and slams the ground; the **shockwave** bounces players on the floor of the same layer, jumping dodges it | `EnemyMutant` (hammer man + shockwave) |
## | 5_e | claw arm + spider legs | **buried underground** (a tread on the floor as the warning), emerges when someone comes near, chases, spins in place up close hitting both sides | `EnemyBurrower` (D's chase + ambush + spin) |
## | 5_d | machine-gun head + treads | **a stationary turret**, turns to face you, three-round bursts, fires diagonally | turret (`EnemyTurret`), pure data |
## | 5_f | emitter + mount | **hangs still upside down from the ceiling**, charges when someone walks below, drips poison that bursts into a poison cloud on landing | `EnemyCeilingEmitter` + `PoisonDrip` |

const PACK := "res://skins/lab/lab_skin.tres"
const ART := "res://skins/lab"
const GROUND_Y := 320.0
const STAND_Y := 304.0
const SCENES := {
	&"5_a": "res://scenes/enemy_5_a.tscn", &"5_b": "res://scenes/enemy_5_b.tscn",
	&"5_c": "res://scenes/enemy_5_c.tscn", &"5_d": "res://scenes/enemy_5_d.tscn",
	&"5_e": "res://scenes/enemy_5_e.tscn",
	&"5_f": "res://scenes/enemy_5_f.tscn",
}


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func spawn(key: StringName, at: Vector2) -> Enemy:
	var enemy := (load(SCENES[key]) as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(enemy)
	enemy.global_position = at
	return enemy


## Ground only (the test level has 6 one-way platforms and two walls of its own, which would block flasks and sight).
func open_floor(skin: SkinPack = null) -> void:
	await reset_scene(false, false, skin)
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and slab.one_way:
			slab.free()


func add_ledge(x: float, top: float, wide := 160.0) -> Platform:
	var ledge: Platform = load("res://scenes/platform.tscn").instantiate()
	ledge.one_way = true
	ledge.position = Vector2(x, top)
	ledge.size = Vector2(wide, 16)
	main.get_node("Level").add_child(ledge)
	return ledge


func flasks() -> Array:
	return main.get_node("Enemies").get_children().filter(func(n: Node) -> bool:
		return n is Grenade and (n as Grenade).blast_event == &"acid_splash")


func mutants() -> Array:
	return main.get_node("Enemies").get_children().filter(func(n: Node) -> bool: return n is EnemyMutant)


# ---------------------------------------------------------------- Scientists: acid flasks

func test_the_scientist_throws_an_acid_flask_at_you() -> void:
	await open_floor()
	var scientist := spawn(&"5_a", Vector2(400, STAND_Y)) as EnemyScientist
	scientist.facing = -1
	player.global_position = Vector2(220, STAND_Y)
	snap_camera()
	var thrown := false
	for i in 120:
		await tree.physics_frame
		if not flasks().is_empty():
			thrown = true
			break
	check("it throws something", thrown)
	if not thrown:
		return
	var flask := flasks()[0] as Grenade
	check("an acid flask (splashes green, not a fireball)", flask.blast_event == &"acid_splash")
	check("aimed at players, not at its friends", flask.target_layer == 2, str(flask.target_layer))
	check("it shatters on the first thing it touches (no bounce)", flask.bounces == 0, str(flask.bounces))
	check("and it did not turn into a mutant just for seeing you", not scientist.is_transforming())


func test_a_flask_splash_hurts_and_is_drawn_as_acid() -> void:
	await open_floor()
	player.global_position = Vector2(300, STAND_Y)
	await frames(2)
	var full := player.health
	# A flask dropped from above the player's head: it shatters on hitting them (no bounce)
	var flask := (load("res://scenes/acid_flask.tscn") as PackedScene).instantiate() as Grenade
	flask.launch(Vector2.DOWN)
	main.get_node("Enemies").add_child(flask)
	flask.global_position = Vector2(300, STAND_Y - 60.0)
	await frames(40)
	check("the splash hurts whoever it lands on", player.health < full, "%d -> %d" % [full, player.health])
	check("and it is reported as an acid splash, not an explosion",
		events.has(&"acid_splash") and not events.has(&"explosion"), str(events))


# ---------------------------------------------------------------- Scientists: transforming

func test_a_wounded_scientist_turns_into_a_mutant() -> void:
	await open_floor()
	var scientist := spawn(&"5_a", Vector2(400, STAND_Y)) as EnemyScientist
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	scientist.take_damage(SHOT, Vector2.INF, player)
	check("one shot short of dead: it starts to change", scientist.is_transforming())
	var where := scientist.global_position
	await frames(int(scientist.transform_time * 60.0) + 6)
	check("the scientist is gone", not is_instance_valid(scientist))
	check("a mutant stands where it was", mutants().size() == 1
		and (mutants()[0] as Node2D).global_position.distance_to(where) < 24.0)
	check("no reward for the scientist (the mutant carries it)", not events.has(&"enemy_death"), str(events))


func test_a_scientist_killed_outright_never_changes() -> void:
	await open_floor()
	var scientist := spawn(&"5_a", Vector2(400, STAND_Y)) as EnemyScientist
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	scientist.take_damage(scientist.health, Vector2.INF, player)
	await frames(int(scientist.transform_time * 60.0) + 6)
	check("dead in one go: no mutant", mutants().is_empty())
	check("and it paid out like any enemy", events.has(&"enemy_death"))


func test_getting_close_makes_the_scientist_change() -> void:
	await open_floor()
	var scientist := spawn(&"5_a", Vector2(400, STAND_Y)) as EnemyScientist
	scientist.set_physics_process(false)
	player.global_position = Vector2(400 - scientist.transform_range + 10.0, STAND_Y)
	await frames(2)
	scientist.set_physics_process(true)
	await frames(4)
	check("walking right up to it sets it off", scientist.is_transforming())


func test_the_grey_scientist_changes_as_soon_as_it_sees_you() -> void:
	await open_floor()
	var scientist := spawn(&"5_b", Vector2(400, STAND_Y)) as EnemyScientist
	scientist.facing = -1
	player.global_position = Vector2(200, STAND_Y)
	snap_camera()
	await frames(6)
	check("it changes on sight", scientist.is_transforming())
	check("without throwing anything first", flasks().is_empty())


func test_the_change_is_a_window_to_kill_it() -> void:
	await open_floor()
	var scientist := spawn(&"5_b", Vector2(400, STAND_Y)) as EnemyScientist
	scientist.facing = -1
	player.global_position = Vector2(200, STAND_Y)
	snap_camera()
	await frames(6)
	check("setup: it is changing", scientist.is_transforming())
	scientist.take_damage(scientist.health, Vector2.INF, player)
	await frames(int(scientist.transform_time * 60.0) + 6)
	check("shot dead mid-change: no mutant comes out", mutants().is_empty())
	check("and it counts as a kill", events.has(&"enemy_death"))


func test_a_changing_scientist_stands_still() -> void:
	await open_floor()
	var scientist := spawn(&"5_a", Vector2(400, STAND_Y)) as EnemyScientist
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	scientist.start_transform()
	var x := scientist.global_position.x
	await frames(int(scientist.transform_time * 60.0) - 6)
	check("it does not walk while changing", absf(scientist.global_position.x - x) < 1.0,
		"%.1f -> %.1f" % [x, scientist.global_position.x])


# ---------------------------------------------------------------- Mutant: ground slam + shockwave

func slam_now(mutant: EnemyMutant) -> void:
	mutant.set_physics_process(false)
	mutant._land_the_blow()


func test_the_slam_shakes_people_standing_nearby_on_its_floor() -> void:
	await open_floor()
	var mutant := spawn(&"5_c", Vector2(400, STAND_Y)) as EnemyMutant
	mutant.set_physics_process(false)
	mutant.facing = -1
	player.global_position = Vector2(400 - mutant.shock_radius + 12.0, STAND_Y)
	await frames(10)
	check("setup: the player is out of the hammer's reach", player.body_center().distance_to(mutant.smash_point())
		> mutant.smash_radius)
	var full := player.health
	slam_now(mutant)
	await frames(2)
	check("the shockwave still hurts", player.health < full, "%d -> %d" % [full, player.health])
	check("and throws you up off the floor", player.velocity.y < 0.0 or not player.is_on_floor(),
		"vy %.0f" % player.velocity.y)


func test_jumping_clears_the_shockwave() -> void:
	await open_floor()
	var mutant := spawn(&"5_c", Vector2(400, STAND_Y)) as EnemyMutant
	mutant.set_physics_process(false)
	mutant.facing = -1
	player.global_position = Vector2(400 - mutant.shock_radius + 12.0, STAND_Y)
	await frames(10)
	Input.action_press("jump")
	await frames(8)
	release_all_input()
	check("setup: the player is in the air", not player.is_on_floor())
	var full := player.health
	slam_now(mutant)
	await frames(2)
	check("in the air the shockwave misses you", player.health == full, "%d -> %d" % [full, player.health])


func test_the_shockwave_stays_on_its_own_floor() -> void:
	await open_floor()
	var mutant := spawn(&"5_c", Vector2(400, STAND_Y)) as EnemyMutant
	mutant.set_physics_process(false)
	mutant.facing = -1
	var ledge := add_ledge(300, 240, 120)
	player.global_position = Vector2(360, ledge.position.y - 16.0)
	await frames(10)
	check("setup: the player stands on a ledge above", player.is_on_floor()
		and player.global_position.y < STAND_Y - 40.0)
	var full := player.health
	slam_now(mutant)
	await frames(2)
	check("standing on a ledge above, the shockwave does not reach you", player.health == full,
		"%d -> %d" % [full, player.health])


func test_out_of_range_the_shockwave_does_nothing() -> void:
	await open_floor()
	var mutant := spawn(&"5_c", Vector2(400, STAND_Y)) as EnemyMutant
	mutant.set_physics_process(false)
	mutant.facing = -1
	player.global_position = Vector2(400 - mutant.shock_radius - 30.0, STAND_Y)
	await frames(10)
	var full := player.health
	slam_now(mutant)
	await frames(2)
	check("beyond its radius you are safe", player.health == full, "%d -> %d" % [full, player.health])


# ---------------------------------------------------------------- Skin pack

func test_the_pack_draws_the_lab_enemies() -> void:
	if needs_art(): return
	for key: StringName in SCENES:
		var scene := pack().find_appearance(key)
		check("the pack has art for %s" % key, scene != null and scene.resource_path.contains("lab"), str(scene))
	for key: StringName in [&"5_a", &"5_b"]:
		check("%s has its change into a mutant" % key,
			ResourceLoader.exists("%s/enemies/%s/transform_r.png" % [ART, key]))
	check("the flask has a sprite", pack().find_appearance(&"acid_flask") != null)
	check("the splash has an effect", pack().effects.has(&"acid_splash"))


func test_the_change_holds_on_the_mutant_frame_in_the_pack() -> void:
	if needs_art(): return
	await open_floor(pack())
	var scientist := spawn(&"5_a", Vector2(400, STAND_Y)) as EnemyScientist
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	scientist.start_transform()
	var look := scientist.get_node("Visual") as EnemySpriteAppearance
	check("setup: the pack draws it", look != null)
	if look == null:
		return
	await frames(int(look.once_length(&"transform") * 60.0) + 4)
	check("after the change animation it holds on the last (mutant) frame, not back to idle",
		look.clip() == &"transform", str(look.clip()))
	check("the change is drawn long enough to see", look.once_length(&"transform") <= scientist.transform_time,
		"%.2f vs %.2f" % [look.once_length(&"transform"), scientist.transform_time])


func test_every_one_runs_in_the_pack_without_errors() -> void:
	if needs_art(): return
	await open_floor(pack())
	var x := 260.0
	for key: StringName in SCENES:
		spawn(key, Vector2(x, STAND_Y))
		x += 80.0
	player.global_position = Vector2(120, STAND_Y)
	player.grant_invincibility(10.0)
	snap_camera()
	await frames(240)
	check("four seconds of the lab enemies in the pack ran clean", true)


# ---------------------------------------------------------------- 5-D stationary turret

func enemy_bullets() -> Array:
	return main.get_node("Enemies").get_children().filter(func(n: Node) -> bool: return n is Bullet)


func test_the_lab_turret_never_moves() -> void:
	await open_floor()
	var turret := spawn(&"5_d", Vector2(420, STAND_Y)) as Enemy
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(10.0)
	snap_camera()
	var start := turret.global_position
	await frames(150)
	check("in two and a half seconds of firing it has not moved", turret.global_position.distance_to(start) < 1.0,
		"%s -> %s" % [start, turret.global_position])


func test_the_lab_turret_turns_to_you_and_fires_bursts_of_three() -> void:
	await open_floor()
	var turret := spawn(&"5_d", Vector2(420, STAND_Y)) as Enemy
	turret.facing = 1
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(10.0)
	snap_camera()
	var most := 0
	for i in 90:
		await tree.physics_frame
		most = maxi(most, enemy_bullets().size())
	check("it turned round to face you", turret.facing == -1)
	check("a burst of three in the air at once", most >= 3, str(most))


func test_the_lab_turret_shoots_up_at_a_ledge() -> void:
	await open_floor()
	var turret := spawn(&"5_d", Vector2(420, STAND_Y)) as Enemy
	var ledge := add_ledge(240, 200, 100)
	player.global_position = Vector2(290, ledge.position.y - 16.0)
	player.grant_invincibility(10.0)
	snap_camera()
	var diagonal := false
	for i in 120:
		await tree.physics_frame
		for b in enemy_bullets():
			if (b as Bullet).direction.y < -0.3:
				diagonal = true
	check("it fires up at 45 degrees at someone on a ledge", diagonal)


# ---------------------------------------------------------------- 5-F poison emitter on the ceiling

## The ceiling: a solid slab with its bottom at y 120; the top of the emitter's mount touches it.
func ceiling_emitter(x: float) -> EnemyCeilingEmitter:
	var slab: Platform = load("res://scenes/platform.tscn").instantiate()
	slab.position = Vector2(x - 80.0, 104.0)
	slab.size = Vector2(160, 16)
	main.get_node("Level").add_child(slab)
	return spawn(&"5_f", Vector2(x, 120.0 + EnemyCeilingEmitter.MOUNT)) as EnemyCeilingEmitter


func clouds() -> Array:
	return tree.get_nodes_in_group(PoisonCloud.GROUP)


func test_the_emitter_hangs_without_falling() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	player.global_position = Vector2(100, STAND_Y)
	var start := emitter.global_position
	await frames(60)
	check("it stays up on the ceiling", emitter.global_position.distance_to(start) < 1.0,
		"%s -> %s" % [start, emitter.global_position])


func test_walking_under_the_emitter_gets_you_gassed() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	player.global_position = Vector2(400, STAND_Y)
	await frames(4)
	check("someone below: it starts charging (the warning)", emitter.is_charging())
	var gassed := false
	for i in 120:
		await tree.physics_frame
		if not clouds().is_empty():
			gassed = true
			break
	check("the drip lands and becomes a cloud of gas", gassed)
	if gassed:
		var cloud := clouds()[0] as Node2D
		check("right below the emitter, down at your feet", absf(cloud.global_position.x - 400.0) < 12.0
			and cloud.global_position.y > STAND_Y - 30.0, str(cloud.global_position))
	await frames(10)
	check("standing there poisons you", player.statuses.has(&"poison"))


func test_the_emitter_warns_before_it_drips() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	player.global_position = Vector2(400, STAND_Y)
	await frames(4)
	check("setup: charging", emitter.is_charging())
	check("the charge is long enough to see and dodge", emitter.charge_time >= 0.4, str(emitter.charge_time))
	await frames(int(emitter.charge_time * 60.0) - 6)
	var drips := main.get_node("Enemies").get_children().filter(func(n: Node) -> bool: return n is PoisonDrip)
	check("nothing drips while it is still charging", drips.is_empty())


func test_the_emitter_ignores_you_off_to_the_side() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	player.global_position = Vector2(400 + emitter.trigger_width + 40.0, STAND_Y)
	await frames(60)
	check("not underneath it: nothing happens", not emitter.is_charging() and clouds().is_empty())


func test_the_emitter_rests_between_drips() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	player.global_position = Vector2(400, STAND_Y)
	player.grant_invincibility(10.0)
	var drips := 0
	var seen := {}
	for i in int((emitter.charge_time + emitter.cooldown * 0.8) * 60.0):
		await tree.physics_frame
		for n in main.get_node("Enemies").get_children():
			if n is PoisonDrip and not seen.has(n.get_instance_id()):
				seen[n.get_instance_id()] = true
				drips += 1
	check("one drip, then a rest (not a stream)", drips == 1, str(drips))


func test_a_drip_lands_on_a_ledge_too() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	var ledge := add_ledge(340, 240, 120)
	player.global_position = Vector2(400, ledge.position.y - 16.0)
	var gassed := false
	for i in 120:
		await tree.physics_frame
		if not clouds().is_empty():
			gassed = true
			break
	check("the gas comes up on the ledge, not through it", gassed
		and absf((clouds()[0] as Node2D).global_position.y - (ledge.position.y - 18.0)) < 14.0,
		str(clouds()[0].global_position) if gassed else "no cloud")


func test_the_emitter_can_be_shot_from_below() -> void:
	await open_floor()
	var emitter := ceiling_emitter(400)
	emitter.set_physics_process(false)
	player.global_position = Vector2(400, STAND_Y)
	await frames(4)
	var full := emitter.health
	player._shoot(Vector2.UP)
	await frames(30)
	check("a shot straight up hits it", emitter.health < full, "%d -> %d" % [full, emitter.health])


func test_the_big_mechs_blow_up_instead_of_falling_over() -> void:
	if needs_art(): return
	await open_floor(pack())
	var turret := spawn(&"5_d", Vector2(420, STAND_Y)) as Enemy
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	var look := turret.get_node("Visual") as Node2D
	turret.take_damage(turret.health, Vector2.INF, player)
	await frames(4)
	check("the mech's picture is gone straight away (no death art to play)", not is_instance_valid(look))
	var booms := main.get_node("Fx").get_children().filter(func(n: Node) -> bool:
		return n.scene_file_path.contains("explosion"))
	check("and an explosion goes off where it stood", not booms.is_empty())


func test_a_drip_with_nobody_below_bursts_on_the_floor() -> void:
	# In the two cases above someone stands underneath, and the drip bursts on them — landing on the floor needs a case of its own
	await open_floor()
	player.global_position = Vector2(100, STAND_Y)
	var drip := (load("res://scenes/poison_drip.tscn") as PackedScene).instantiate() as PoisonDrip
	drip.launch(Vector2.DOWN)
	main.get_node("Enemies").add_child(drip)
	drip.global_position = Vector2(420, 140)
	var gassed := false
	for i in 90:
		await tree.physics_frame
		if not clouds().is_empty():
			gassed = true
			break
	check("it bursts on the floor", gassed and absf((clouds()[0] as Node2D).global_position.y - (GROUND_Y - 18.0)) < 10.0,
		str(clouds()[0].global_position) if gassed else "no cloud")


# ---------------------------------------------------------------- 5-E spider claw arm emerging from the ground

func burrower(x: float) -> EnemyBurrower:
	return spawn(&"5_e", Vector2(x, STAND_Y)) as EnemyBurrower


func test_a_buried_burrower_cannot_be_hit_or_touched() -> void:
	await open_floor()
	var digger := burrower(420)
	player.global_position = Vector2(100, STAND_Y)
	await frames(4)
	check("setup: it starts buried", digger.is_buried())
	check("buried, it has no collision layer (bullets and bodies pass over it)", digger.collision_layer == 0)
	var full := digger.health
	digger.hit_by_ultimate(player)
	await frames(2)
	check("the ultimate cannot reach it underground", is_instance_valid(digger) and digger.health == full)
	var start := digger.global_position
	await frames(60)
	check("and it waits where it is", digger.global_position.distance_to(start) < 1.0)


func test_it_stays_down_until_you_come_close_on_its_floor() -> void:
	await open_floor()
	var digger := burrower(420)
	player.global_position = Vector2(420 - digger.trigger_range - 60.0, STAND_Y)
	await frames(30)
	check("far away: it stays buried", digger.state == EnemyBurrower.State.BURIED)
	var ledge := add_ledge(360, 200, 120)
	player.global_position = Vector2(420, ledge.position.y - 16.0)
	await frames(30)
	check("right above it on a ledge: still buried (not its floor)", digger.state == EnemyBurrower.State.BURIED)


func test_coming_close_makes_it_burst_out() -> void:
	await open_floor()
	var digger := burrower(420)
	player.global_position = Vector2(420 - digger.trigger_range + 20.0, STAND_Y)
	await frames(3)
	check("close on its floor: it starts coming out", digger.state == EnemyBurrower.State.EMERGING)
	check("still untouchable while it climbs out", digger.collision_layer == 0)
	await frames(int(digger.emerge_time * 60.0) + 4)
	check("out: it can be hit again", digger.collision_layer != 0)
	check("and it is hunting", digger.state != EnemyBurrower.State.BURIED
		and digger.state != EnemyBurrower.State.EMERGING)


func test_out_of_the_ground_it_chases_you() -> void:
	await open_floor()
	var digger := burrower(420)
	player.global_position = Vector2(330, STAND_Y)
	player.grant_invincibility(10.0)
	await frames(int(digger.emerge_time * 60.0) + 6)
	player.global_position = Vector2(160, STAND_Y)
	var start := digger.global_position.x
	await frames(60)
	check("it walks after you on its spider legs", digger.global_position.x < start - 40.0,
		"%.0f -> %.0f" % [start, digger.global_position.x])


func emerged_burrower(x: float) -> EnemyBurrower:
	var digger := burrower(x)
	digger.state = EnemyBurrower.State.HUNTING
	digger.collision_layer = 8
	return digger


func test_up_close_it_spins_and_hits_both_sides() -> void:
	for side: float in [-1.0, 1.0]:
		await open_floor()
		var digger := emerged_burrower(400)
		digger.facing = -1
		await frames(4)
		player.global_position = Vector2(400 + side * 30.0, STAND_Y)
		await frames(2)
		var full := player.health
		var flips := 0
		var last := digger.facing
		var spun := false
		for i in 60:
			await tree.physics_frame
			if digger.is_spinning():
				spun = true
				if digger.facing != last:
					flips += 1
			last = digger.facing
		check("someone close on the %s: it spins" % ("left" if side < 0 else "right"), spun)
		check("whirling round (it turns several times)", flips >= 3, str(flips))
		check("and the spin hits you on the %s too" % ("left" if side < 0 else "right"), player.health < full,
			"%d -> %d" % [full, player.health])


func test_after_a_spin_it_catches_its_breath() -> void:
	await open_floor()
	var digger := emerged_burrower(400)
	digger.set_physics_process(false)
	player.global_position = Vector2(370, STAND_Y)
	player.grant_invincibility(10.0)
	await frames(2)
	digger.set_physics_process(true)
	digger._start_spin()
	await frames(int(digger.spin_time * 60.0) + 2)
	check("after spinning it rests", digger.is_resting())
	var x := digger.global_position.x
	await frames(int(digger.rest_time * 60.0) - 6)
	check("standing still — the moment to hit back", absf(digger.global_position.x - x) < 1.0)


func test_a_buried_one_shows_as_a_faint_block_without_art() -> void:
	await open_floor()
	var digger := burrower(420)
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	var look := digger.get_node("Visual") as Appearance
	check("placeholder: a faint block marks the spot", look.modulate.a < 0.5, str(look.modulate.a))
	player.global_position = Vector2(360, STAND_Y)
	await frames(int(digger.emerge_time * 60.0) + 6)
	check("out of the ground: fully visible", look.modulate.a > 0.99, str(look.modulate.a))


func test_in_the_pack_only_the_treads_show_until_it_comes_out() -> void:
	if needs_art(): return
	await open_floor(pack())
	var digger := burrower(420)
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)
	var look := digger.get_node("Visual") as EnemySpriteAppearance
	check("setup: the pack draws it", look != null)
	if look == null:
		return
	check("buried: it shows the first frame of coming out (just the treads)",
		look.clip() == &"emerge" and (look.get_node("Body") as Sprite2D).frame == 0, str(look.clip()))
	player.global_position = Vector2(360, STAND_Y)
	await frames(4)
	check("coming out: the climb-out plays", look.clip() == &"emerge")
	check("and the climb-out is no longer than the time it is untouchable",
		look.once_length(&"emerge") <= digger.emerge_time + 0.01,
		"%.2f vs %.2f" % [look.once_length(&"emerge"), digger.emerge_time])
