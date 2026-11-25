extends GameTest
## Stage 4's boss, the "skull" (`scripts/boss_skull.gd`), and the little skulls it summons (`scripts/skull_minion.gd`).
##
## Run on the test level: clear the level's own floating platforms (otherwise "where the laser reaches" and "changing layers" would measure the level's existing things),
## and put the boss on the right at its lowest position, where the laser lines up with a player standing on the ground (placed as in stage 4: ground 320 → 288).

const PACK := "res://skins/basement/basement_skin.tres"
const GROUND_Y := 320.0
const STAND_Y := 304.0
const BOSS_AT := Vector2(544, 288)


func open_arena(skin: SkinPack = null) -> void:
	await reset_scene(false, false, skin)
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and slab.one_way:
			slab.free()


func spawn_boss() -> BossSkull:
	var boss := (load("res://scenes/boss_4.tscn") as PackedScene).instantiate() as BossSkull
	main.get_node("Enemies").add_child(boss)
	boss.global_position = BOSS_AT
	boss._home = BOSS_AT
	boss._lanes = [BOSS_AT.x, BOSS_AT.x + boss.lane_offset]
	return boss


func add_ledge(x: float, top: float, wide := 160.0) -> Platform:
	var ledge: Platform = load("res://scenes/platform.tscn").instantiate()
	ledge.one_way = true
	ledge.position = Vector2(x, top)
	ledge.size = Vector2(wide, 16)
	main.get_node("Level").add_child(ledge)
	return ledge


## Wait until it enters a given state (at most n frames).
func wait_for(boss: BossSkull, state: Callable, n := 300) -> bool:
	for i in n:
		if state.call():
			return true
		await tree.physics_frame
	return state.call()


# ---------------------------------------------------------------- Identity

func test_it_is_a_floating_boss() -> void:
	var boss := (load("res://scenes/boss_4.tscn") as PackedScene).instantiate() as BossSkull
	check("it is a boss", boss is Boss)
	check("it floats", boss.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING)
	check("and does not fall before it appears", is_zero_approx(boss.gravity))
	check("it brings minions to summon", boss.minion_scene != null)
	boss.free()


func test_the_pack_has_its_art() -> void:
	if needs_art(): return
	var pack := load(PACK) as SkinPack
	for key: StringName in [&"4_boss", &"4_minion"]:
		check("%s is in the pack" % key, pack.appearances.has(key))
	for clip: String in ["idle", "charge", "beam", "summon", "sneer", "hurt", "death"]:
		check("the boss has %s" % clip,
			ResourceLoader.exists("res://skins/basement/enemies/4_boss/%s_r.png" % clip))
	for clip: String in ["idle", "walk", "hurt", "death"]:
		check("the minion has %s" % clip,
			ResourceLoader.exists("res://skins/basement/enemies/4_minion/%s_r.png" % clip))
	check("and a beam to tile", ResourceLoader.exists("res://skins/basement/enemies/4_boss/beam_thick.png"))


# ---------------------------------------------------------------- Laser

func test_it_lines_up_charges_then_fires() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	var full := player.health
	var charged := await wait_for(boss, func() -> bool: return boss.is_charging())
	check("it starts charging", charged)
	check("lined up on the player's body", absf(boss.beam_height() - player.body_center().y) <= 1.0,
		"%.1f vs %.1f" % [boss.beam_height(), player.body_center().y])
	# **Measure how long the charge lasted**, not just whether it happened: with a charge time of 0 the state still flickers "charging" for one frame
	var held := 0
	while boss.is_charging() and held < 120:
		await tree.physics_frame
		held += 1
		if boss.is_charging():
			check("nothing hurts while it charges — that is the warning", player.health == full,
				"%d -> %d at frame %d" % [full, player.health, held])
	check("the warning lasts long enough to react to", held >= 30, "%d frames" % held)
	var fired := await wait_for(boss, func() -> bool: return boss.is_firing(), 30)
	check("then it fires", fired)
	await frames(3)
	check("and the beam hits", player.health < full, "%d -> %d" % [full, player.health])


func test_the_beam_runs_to_the_wall_through_ledges() -> void:
	await open_arena()
	var boss := spawn_boss()
	add_ledge(200, boss.global_position.y + BossSkull.BEAM_ORIGIN.y - 8.0, 120)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await wait_for(boss, func() -> bool: return boss.is_firing())
	var wall := main.get_node("Level/WallLeft") as Platform
	var wall_face := wall.position.x + wall.size.x
	check("it fires across the whole level, to the far wall", absf(boss.beam_end().x - wall_face) < 2.0,
		"ends at %.0f, wall at %.0f" % [boss.beam_end().x, wall_face])


func test_another_floor_is_safe() -> void:
	# The dodge is changing layers: once the laser is locked, jumping up one layer (60 tall) gets out of its way
	await open_arena()
	var boss := spawn_boss()
	var ledge := add_ledge(240, GROUND_Y - 60.0, 160)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await wait_for(boss, func() -> bool: return boss.is_charging())
	player.global_position = Vector2(300, ledge.position.y - 16.0)
	var full := player.health
	await wait_for(boss, func() -> bool: return boss.is_firing(), 60)
	await frames(int(boss.beam_time * 60.0))
	check("one floor up, the beam passes under you", player.health == full, "%d -> %d" % [full, player.health])


func test_lying_down_under_it_also_works() -> void:
	# The laser aims at a standing player's body centre and is 6px thick; a prone player fits under it
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await wait_for(boss, func() -> bool: return boss.is_charging())
	Input.action_press("crouch")
	await frames(4)
	var full := player.health
	await wait_for(boss, func() -> bool: return boss.is_firing(), 60)
	await frames(int(boss.beam_time * 60.0))
	release_all_input()
	check("setup: the player really lay down", player.hit_box().size.y < 20.0, str(player.hit_box()))
	check("and the beam went over", player.health == full, "%d -> %d" % [full, player.health])


# ---------------------------------------------------------------- Bone shots (standing under it is not safe)

## Record the direction of every shot the boss fires.
func record_shots(boss: BossSkull) -> Array[Vector2]:
	var shots: Array[Vector2] = []
	boss.shot_fired.connect(func() -> void: shots.append(boss.last_shot_direction))
	return shots


func test_standing_under_it_is_not_safe() -> void:
	# 2026-10 playtest feedback: the laser shoots from the bony hand toward the middle of the shaft, so standing right under it was a safe spot. Now it fires bone shots downward
	await open_arena()
	var boss := spawn_boss()
	boss.summon_every = 1000
	# Lift it a bit: at its lowest position its bony hand is as high as a player standing on the ground, who is then actually beside and behind it
	boss.global_position.y = BOSS_AT.y - 120.0
	player.global_position = Vector2(BOSS_AT.x, STAND_Y)
	snap_camera()
	var shots := record_shots(boss)
	var full := player.health
	await frames(240)
	check("it shoots at a player right under it", not shots.is_empty(), str(shots.size()))
	check("downwards", shots.size() > 0 and shots[0].y > 0.5, str(shots))
	check("and it hurts", player.health < full, "%d -> %d" % [full, player.health])


func test_it_shoots_up_at_a_player_above_its_reach() -> void:
	await open_arena()
	var boss := spawn_boss()
	boss.summon_every = 1000
	# It floats up 140 at most, so the highest the laser reaches is 288 - 140 + 16 = 164; standing higher than that, the laser cannot reach
	var ledge := add_ledge(400, 100, 200)
	player.global_position = Vector2(480, ledge.position.y - 16.0)
	snap_camera()
	var shots := record_shots(boss)
	await frames(240)
	check("it shoots at a player above its reach", not shots.is_empty(), str(shots.size()))
	check("upwards", shots.size() > 0 and shots[0].y < -0.5, str(shots))


func test_the_volley_is_a_fan() -> void:
	await open_arena()
	var boss := spawn_boss()
	boss.summon_every = 1000
	player.global_position = Vector2(BOSS_AT.x, STAND_Y)
	snap_camera()
	var shots := record_shots(boss)
	await wait_for(boss, func() -> bool: return shots.size() >= boss.burst_max, 240)
	check("a full volley", shots.size() >= boss.burst_max, str(shots.size()))
	if shots.size() < boss.burst_max:
		return
	var first := shots.slice(0, boss.burst_max)
	var widest := 0.0
	for d: Vector2 in first:
		widest = maxf(widest, absf(rad_to_deg(d.angle_to(first[boss.burst_max / 2]))))
	check("spread out, not one line", widest >= boss.volley_spread * 1.5, "%.0f°" % widest)


func test_the_volley_in_the_pack_needs_no_missing_art() -> void:
	if needs_art(): return
	# Caught in a screenshot: the base class makes the appearance "play the firing clip once" for every shot, and the skull has no attack_level clip,
	# so every shot printed a "Resource file not found" (stage 2's 2-C once had the same problem). The default skin cannot catch it
	await open_arena(load(PACK) as SkinPack)
	var boss := spawn_boss()
	boss.summon_every = 1000
	boss.global_position.y = BOSS_AT.y - 120.0
	player.global_position = Vector2(BOSS_AT.x, STAND_Y)
	snap_camera()
	var shots := record_shots(boss)
	# **Check for the sprites yourself**: "Resource file not found" is an engine error printed by the loader,
	# and the runner only counts SCRIPT ERROR as failures, not this (the first version of the case passed just like that)
	var visual := boss.get_node("Visual") as EnemySpriteAppearance
	var missing := {}
	for i in 240:
		await tree.physics_frame
		var file := "%s/%s_l.png" % [visual.art_dir, visual.clip()]
		if not ResourceLoader.exists(file):
			missing[file] = true
	check("setup: it volleyed in the pack's skin", not shots.is_empty(), str(shots.size()))
	check("and every pose it showed has art", missing.is_empty(), str(missing.keys()))


# ---------------------------------------------------------------- Little skulls: flying everywhere, swooping

func spawn_minion(at: Vector2) -> SkullMinion:
	var minion := (load("res://scenes/enemy_4_minion.tscn") as PackedScene).instantiate() as SkullMinion
	main.get_node("Enemies").add_child(minion)
	minion.global_position = at
	return minion


func test_minions_fly_through_solid_ground() -> void:
	# They used to be blocked by one-way platforms and solid blocks, and could not reach a player hiding under the boss. Now they pass through walls
	await open_arena()
	var slab: Platform = load("res://scenes/platform.tscn").instantiate()
	slab.position = Vector2(200, 200)
	slab.size = Vector2(240, 20)
	main.get_node("Level").add_child(slab)
	var minion := spawn_minion(Vector2(320, 150))
	minion._left = 100.0
	player.global_position = Vector2(320, STAND_Y)
	snap_camera()
	# It circles the player (random direction and phase), so looking at the last frame only, it might happen to be above and be judged "did not come through" —
	# that happened once in a full run. Look at the lowest point it reached in these two seconds
	var lowest := minion.global_position.y
	for i in 120:
		await tree.physics_frame
		if is_instance_valid(minion):
			lowest = maxf(lowest, minion.global_position.y)
	check("it got through the slab to the player", lowest > 220.0, "lowest %.0f" % lowest)


func test_minions_wind_up_then_dive_fast_and_straight() -> void:
	await open_arena()
	var minion := spawn_minion(Vector2(420, 200))
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	minion._left = 0.0
	var wound := 0
	for i in 60:
		await tree.physics_frame
		if minion.is_winding_up():
			wound += 1
		if minion.is_diving():
			break
	check("it warns before it dives", wound >= 20, "%d frames" % wound)
	check("then dives", minion.is_diving())
	var heading := minion._dive
	player.global_position = Vector2(100, STAND_Y)
	var before := minion.global_position
	await frames(6)
	var moved := (minion.global_position - before).length() / (6.0 / 60.0)
	check("faster than the player walks", moved > player.move_speed, "%.0f px/s" % moved)
	check("and it does not steer after you", minion._dive == heading)


func test_minions_never_leave_the_screen() -> void:
	await open_arena()
	var minion := spawn_minion(Vector2(320, 200))
	player.global_position = Vector2(320, STAND_Y)
	snap_camera()
	minion.state = SkullMinion.State.DIVE
	minion._dive = Vector2.UP
	minion._left = 5.0
	await frames(90)
	check("it is still on screen", camera_rig().view_rect().has_point(minion.global_position),
		"%s in %s" % [minion.global_position, camera_rig().view_rect()])


# ---------------------------------------------------------------- Summoning, switching sides

func test_every_third_attack_is_a_summon() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	boss._attacks = boss.summon_every - 1
	boss._left = 0.0
	await frames(60)
	check("it summoned", boss.minions().size() == boss.summon_count, str(boss.minions().size()))
	for minion in boss.minions():
		check("a minion is a skull minion", minion is SkullMinion)


func test_never_more_minions_than_the_cap() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	for i in 3:
		boss._summon()
	check("capped", boss.minions().size() <= boss.minion_cap, str(boss.minions().size()))


func test_minions_float_at_you_and_die_in_two_shots() -> void:
	await open_arena()
	var minion := (load("res://scenes/enemy_4_minion.tscn") as PackedScene).instantiate() as SkullMinion
	main.get_node("Enemies").add_child(minion)
	minion.global_position = Vector2(500, 200)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	var start := minion.global_position.distance_to(player.body_center())
	await frames(60)
	check("it drifts towards the player", minion.global_position.distance_to(player.body_center()) < start - 30.0)
	minion.take_damage(GameTest.SHOT)
	check("one shot is not enough", is_instance_valid(minion) and minion.health > 0)
	minion.take_damage(GameTest.SHOT)
	check("two are", not is_instance_valid(minion) or minion.health <= 0)


func test_killing_a_minion_while_the_boss_lives_is_fine() -> void:
	# Crashed in a 2026-10 playtest: after killing a little skull, the boss cleaning up its list every frame passed an already freed object to
	# a typed lambda parameter, printing a SCRIPT ERROR every frame (the editor stopped in the debugger).
	# The old case only tested "the little skulls shatter when the boss dies" and had never killed one while the boss was alive.
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss._summon()
	var minions := boss.minions().duplicate()
	check("setup: there are minions", minions.size() >= 2, str(minions.size()))
	# **free() it directly, not through take_damage**: in real play the player's bullet kills it, and bullets are processed after the boss,
	# so the little skull is freed at the end of that frame — next frame the boss's cleanup sees an already freed object.
	# With take_damage between frames it is only "queued for deletion", the boss drops it on seeing that, and it does not reproduce (the first version passed just like that).
	(minions[0] as Enemy).free()
	await frames(30)
	check("the boss lets go of the dead one", boss.minions().size() == minions.size() - 1,
		str(boss.minions().size()))
	check("and keeps fighting", is_instance_valid(boss) and boss.health > 0)


func test_it_switches_sides_every_other_attack() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	boss._attacks = 1
	boss._left = 0.0
	var swapped := await wait_for(boss, func() -> bool: return boss.is_swapping(), 30)
	check("it heads for the other side", swapped)
	await wait_for(boss, func() -> bool: return not boss.is_swapping(), 240)
	check("and gets there", absf(boss.global_position.x - (BOSS_AT.x + boss.lane_offset)) < 2.0,
		str(boss.global_position.x))
	check("still facing into the shaft", boss.facing == 1)


# ---------------------------------------------------------------- Phase 2

func test_it_turns_nasty_below_half_and_says_so_once() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss.take_damage(boss.max_health / 2 + 1)
	check("enraged", boss.is_enraged())
	boss.take_damage(5)
	var said := events.count(&"boss_enrage")
	check("and it said so exactly once", said == 1, str(said))


func test_enraged_it_fires_twice_a_round() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss.take_damage(boss.max_health / 2 + 1)
	player.set_physics_process(false)
	var beams := 0
	var was_firing := false
	for i in 400:
		await tree.physics_frame
		player.health = player.max_health
		if boss.is_firing() and not was_firing:
			beams += 1
		was_firing = boss.is_firing()
		if boss._move == BossSkull.Move.REST and beams > 0:
			break
	check("two beams in one round", beams == 2, str(beams))


# ---------------------------------------------------------------- Death

func test_its_minions_go_with_it_and_pay_nothing() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss._summon()
	var minions := boss.minions().duplicate()
	check("setup: there are minions", not minions.is_empty())
	# Compare money, not XP: the boss's 400-odd XP levels up a level 1 character, and levelling up resets XP, so the difference is not the reward
	var money := player.progress.money
	var pay := boss.money_reward
	boss.die()
	await frames(2)
	# Do not type the loop variable: they are mostly freed already, and assigning a freed object to a typed variable is an error
	for minion in minions:
		check("a minion went with it", not is_instance_valid(minion) or minion.is_queued_for_deletion())
	check("and only the boss paid", player.progress.money - money == pay,
		"%d vs %d" % [player.progress.money - money, pay])


# ---------------------------------------------------------------- Switching skins

func test_the_pack_draws_the_beam_and_changes_no_rules() -> void:
	var heights := []
	for skin: SkinPack in [null, load(PACK) as SkinPack]:
		await open_arena(skin)
		var boss := spawn_boss()
		player.global_position = Vector2(300, STAND_Y)
		snap_camera()
		await wait_for(boss, func() -> bool: return boss.is_firing())
		heights.append([boss.beam_height(), boss.beam_end().x])
		if skin != null:
			var visual := boss.get_node("Visual")
			check("the pack's look is on", visual is BossSkullAppearance, str(visual))
			if visual is BossSkullAppearance:
				check("and it is drawing the beam", (visual as BossSkullAppearance)._beam_state == 2)
				check("in the firing pose", (visual as BossSkullAppearance).clip() == &"beam",
					str((visual as BossSkullAppearance).clip()))
	check("the same beam in both skins", heights[0] == heights[1], str(heights))
