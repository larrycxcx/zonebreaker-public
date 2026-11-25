extends GameTest
## Ladders (added in 2026-10, preparing for layered stages): `scripts/ladder.gd` + `Player._climb()`.
##
## Build two layers on the test level: a solid floor at y=200 with a 32-wide hole in the middle, and a ladder in the hole down to the ground (320).
## Clear the level's own one-way platforms, so "climbed up" does not measure getting up via some other platform.

const GROUND_Y := 320.0
const UPPER_Y := 200.0
const LADDER_X := 500.0
const PACK := "res://skins/cyberpunk/cyberpunk_skin.tres"


func open_two_floors(skin: SkinPack = null) -> Ladder:
	await reset_scene(false, false, skin)
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and slab.one_way:
			slab.free()
	for span: Vector2 in [Vector2(300, LADDER_X - 16.0), Vector2(LADDER_X + 16.0, 700)]:
		var floor_: Platform = load("res://scenes/platform.tscn").instantiate()
		floor_.position = Vector2(span.x, UPPER_Y)
		floor_.size = Vector2(span.y - span.x, 20)
		main.get_node("Level").add_child(floor_)
	var ladder := (load("res://scenes/ladder.tscn") as PackedScene).instantiate() as Ladder
	ladder.height = GROUND_Y - UPPER_Y
	main.get_node("Level").add_child(ladder)
	ladder.global_position = Vector2(LADDER_X, UPPER_Y)
	return ladder


func feet() -> float:
	return player.global_position.y + 16.0


func hold(action: StringName, n: int) -> void:
	Input.action_press(action)
	await frames(n)
	Input.action_release(action)


func test_up_at_the_foot_climbs_you_to_the_floor_above() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X, GROUND_Y - 16.0)
	await frames(3)
	await hold(&"aim_up", 4)
	check("pressing up grabs the ladder", player.is_climbing())
	Input.action_press(&"aim_up")
	for i in 120:
		await tree.physics_frame
		if not player.is_climbing():
			break
	release_all_input()
	await frames(5)
	check("you get off at the top", not player.is_climbing())
	check("standing on the floor above", absf(feet() - UPPER_Y) < 1.0 and player.is_on_floor(),
		"feet at %.1f" % feet())


func test_you_hang_still_without_input() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X, GROUND_Y - 16.0)
	await frames(3)
	await hold(&"aim_up", 12)
	var y := player.global_position.y
	await frames(30)
	check("still on the ladder", player.is_climbing())
	check("and not sliding down", absf(player.global_position.y - y) < 0.5,
		"%.1f -> %.1f" % [y, player.global_position.y])


func test_walking_over_the_top_does_not_drop_you_in() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X - 60.0, UPPER_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	await frames(40)
	release_all_input()
	check("setup: you crossed the hole", player.global_position.x > LADDER_X + 20.0, str(player.global_position))
	check("without falling in", absf(feet() - UPPER_Y) < 1.0, "feet at %.1f" % feet())


func test_down_on_the_top_takes_you_down_and_lets_go_at_the_bottom() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X, UPPER_Y - 16.0)
	await frames(5)
	check("setup: standing on the ladder top", player.is_on_floor())
	Input.action_press(&"aim_down")
	await frames(3)
	check("pressing down grabs it", player.is_climbing())
	for i in 120:
		await tree.physics_frame
		if not player.is_climbing():
			break
	release_all_input()
	await frames(5)
	check("you let go at the bottom", not player.is_climbing())
	check("standing on the ground", absf(feet() - GROUND_Y) < 1.0, "feet at %.1f" % feet())


func test_no_shooting_on_a_ladder() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X, GROUND_Y - 16.0)
	await frames(3)
	await hold(&"aim_up", 10)
	check("setup: climbing", player.is_climbing())
	Input.action_press(&"shoot")
	await frames(20)
	release_all_input()
	check("not a single bullet", bullets(4).is_empty(), str(bullets(4).size()))


func test_jump_with_a_direction_leaps_off() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X, GROUND_Y - 16.0)
	await frames(3)
	await hold(&"aim_up", 20)
	var x := player.global_position.x
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(3)
	check("you let go", not player.is_climbing())
	await frames(15)
	release_all_input()
	check("and leap the way you pressed", player.global_position.x > x + 20.0,
		"%.0f -> %.0f" % [x, player.global_position.x])


func test_a_hit_knocks_you_off() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X, GROUND_Y - 16.0)
	await frames(3)
	await hold(&"aim_up", 20)
	check("setup: climbing", player.is_climbing())
	player.take_damage(GameTest.HIT, player.global_position + Vector2(20, 0))
	check("a hit knocks you off", not player.is_climbing())


func test_too_far_to_one_side_you_cannot_grab_it() -> void:
	await open_two_floors()
	player.global_position = Vector2(LADDER_X + 20.0, GROUND_Y - 16.0)
	await frames(3)
	await hold(&"aim_up", 6)
	check("off to the side, up is just aiming up", not player.is_climbing())


func test_the_ladder_blocks_nothing_but_its_cap() -> void:
	# Enemies do not climb ladders: to them the ladder does not exist (the cover is a one-way platform they pass through sideways)
	await open_two_floors()
	var ladder := main.get_node("Level").get_children().filter(func(n: Node) -> bool: return n is Ladder)[0] as Ladder
	var bodies := ladder.find_children("*", "CollisionObject2D", true, false)
	check("only the cap has a body", bodies.size() == 1 and bodies[0] == ladder.cap_body(), str(bodies))
	check("and the cap is one-way", ladder.cap_body().one_way)


# ---------------------------------------------------------------- Picture

func test_climbing_shows_the_climb_and_hides_the_gun_arms() -> void:
	if needs_art(): return
	await open_two_floors(load(PACK) as SkinPack)
	player.global_position = Vector2(LADDER_X, GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"aim_up")
	await frames(10)
	var visual := player.get_node("Visual") as SpriteAppearance
	check("setup: the pack's look is on", visual != null)
	if visual == null:
		return
	check("the climbing pose", visual.body_clip() == &"climb", str(visual.body_clip()))
	check("no gun arms", visual.arms_clip() == &"", str(visual.arms_clip()))
	Input.action_release(&"aim_up")
	await frames(3)
	var frame := (visual.get_node("Body") as Sprite2D).frame
	await frames(30)
	check("hanging still, the picture stays still too", (visual.get_node("Body") as Sprite2D).frame == frame)
	release_all_input()


func test_every_zone_can_draw_a_ladder() -> void:
	if needs_art(): return
	for path: String in ["res://skins/cyberpunk/cyberpunk_skin.tres", "res://skins/industrial/industrial_skin.tres",
			"res://skins/bar_street/bar_street_skin.tres", "res://skins/basement/basement_skin.tres"]:
		var scene := (load(path) as SkinPack).find_appearance(&"ladder")
		check("%s has a ladder" % path.get_file(), scene != null)
	for character: String in ["biker", "punk", "cyborg"]:
		check("%s can climb" % character,
			ResourceLoader.exists("res://skins/cyberpunk/%s/body_climb_r.png" % character))
