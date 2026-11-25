extends GameTest
## Visual flipping: scale always stays positive, and left / right flipping is done by mirroring the children's horizontal positions (see VisualFlip).
##
## Why test it specifically: flipping with a negative scale makes the draw rect computed by the ColorRects under Visual wrong
## (shifted by a whole body width with a negative height), the engine culls by it, and characters disappear completely at some positions —
## which is why Boss A occasionally vanished in mid-air. Whether the rect is right can be checked headless too, without real rendering.

## The node paths of the various characters in the stage.
const ACTORS := [
	"Player", "Enemies/WalkerA", "Enemies/WalkerB", "Enemies/WalkerC",
	"Enemies/ChaserD", "Enemies/FlyerE", "Enemies/Turret1", "Enemies/WalkerF", "Enemies/BossMissile",
]


func actors() -> Array:
	var found := []
	for path in ACTORS:
		found.append(main.get_node(path))
	return found


## Make it face a direction. Gameplay only says "I face this way" through the visual layer's interface; the rest it draws by itself.
func face(actor: Node, facing: int) -> void:
	actor.facing = facing
	if actor is Enemy:
		(actor as Enemy)._apply_visual_facing()
	else:
		(actor.get_node("Visual") as Appearance).face(facing)


## All visual blocks under Visual.
func rects(actor: Node) -> Array:
	return actor.get_node("Visual").get_children().filter(func(c): return c is Control)


func test_no_negative_scale() -> void:
	await reset_scene(true)
	for actor in actors():
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			var visual: Node2D = actor.get_node("Visual")
			check("%s: visual scale stays positive facing %d" % [actor.name, facing], visual.scale.x > 0.0, str(visual.scale))


func test_visual_rects_stay_valid() -> void:
	# Every visual block's global rect must have a positive size and really cover the body (this is exactly the rect the engine culls by)
	await reset_scene(true)
	for actor in actors():
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			for rect in rects(actor):
				var r: Rect2 = rect.get_global_rect()
				check("%s/%s facing %d: rect has positive size" % [actor.name, rect.name, facing],
					r.size.x > 0.0 and r.size.y > 0.0, str(r))
				check("%s/%s facing %d: rect sits on the body" % [actor.name, rect.name, facing],
					r.grow(4.0).has_point(actor.global_position) or actor.global_position.distance_to(r.get_center()) < 48.0,
					"%s vs body at %s" % [r, actor.global_position])


func test_facing_left_mirrors_facing_right() -> void:
	# The layout facing left is exactly the mirror of facing right (symmetric pairs like E's left and right wings swap, which also satisfies this)
	await reset_scene(true)
	# Freeze the AI: an enemy that sees the player on screen turns by itself to chase / aim, overriding the facing set here (this only tests visual mirroring)
	for actor in actors():
		if actor is Enemy:
			actor.set_physics_process(false)
	for actor in actors():
		var moved := false
		for child in actor.get_node("Visual").get_children():
			face(actor, 1)
			await frames(1)
			var right := part_center(child)
			face(actor, -1)
			await frames(1)
			var left := part_center(child)
			moved = moved or absf(right) > 0.5
			check("%s/%s mirrors when turning around" % [actor.name, child.name], is_equal_approx(left, -right), "%.2f vs %.2f" % [left, right])
		check("%s has parts that actually change side" % actor.name, moved)


## The horizontal centre of this part (the rect centre for blocks, the point itself for things like muzzles).
func part_center(child: Node) -> float:
	if child is Control:
		return (child as Control).position.x + (child as Control).size.x / 2.0
	return (child as Node2D).position.x


func test_no_judgement_points_under_visual() -> void:
	# Hit points (muzzles, detection rays, hurtboxes…) always hang on the body and must not go into Visual:
	# put in there, changing skins, squashing the visual, even the recoil offset from firing would change the game rules along with it.
	await reset_scene(true)
	for actor in actors():
		for child in actor.get_node("Visual").get_children():
			var judgement: bool = child is Marker2D or child is RayCast2D or child is ShapeCast2D or child is CollisionObject2D
			check("%s/Visual/%s is art, not a judgement point" % [actor.name, child.name], not judgement,
				child.get_class())


func test_muzzles_follow_facing() -> void:
	# The muzzle point has to switch sides with the facing so bullets fly out of the right side.
	# What is checked is the point really used to spawn bullets (computed from the collider), not where some Marker sits.
	await reset_scene(true)
	for actor in actors():
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			var reach := 0.0
			if actor is Player:
				reach = (actor as Player)._muzzle_position(Vector2(facing, 0)).x - actor.global_position.x
			elif (actor as Enemy)._muzzle == null or is_zero_approx((actor as Enemy)._muzzle.position.x):
				continue # D has no muzzle, E fires straight down
			else:
				reach = (actor as Enemy).level_muzzle_position().x - actor.global_position.x
			check("%s: fires from its front when facing %d" % [actor.name, facing], signf(reach) == float(facing),
				"%.1f" % reach)


func test_muzzle_height_comes_from_the_collision_box() -> void:
	# Lying down lowers the collider and the muzzle point has to come down with it — this rule has to depend on the collider, not on the placeholder block being squashed.
	# So the visual is hidden entirely and it is tested again here: the result has to be identical.
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	await frames(5)
	c.set_physics_process(false) # Freeze the AI: the player is not lying down, so it would stand itself back up every frame
	var standing := c.level_muzzle_position().y
	c.get_node("Visual").hide()
	c.get_node("Visual").position = Vector2(0, -200) # Moving the visual away should not affect hit detection either
	await frames(2)
	check("hiding the art does not move the muzzle", is_equal_approx(c.level_muzzle_position().y, standing),
		"%.1f vs %.1f" % [c.level_muzzle_position().y, standing])
	c.set_prone(true)
	await frames(2)
	check("going prone lowers it", c.level_muzzle_position().y > standing + 6.0,
		"%.1f -> %.1f" % [standing, c.level_muzzle_position().y])


# ---------------------------------------------------------------- The visual interface (step 8)

func test_every_character_has_an_appearance_layer() -> void:
	# This is the only interface between gameplay and "what it looks like"
	await reset_scene(true)
	for actor in actors():
		check("%s's Visual is an Appearance" % actor.name, actor.get_node("Visual") is Appearance)


func test_gameplay_runs_on_a_replaced_appearance() -> void:
	# Replace the visuals of the player and enemies entirely with stand-ins that "draw nothing": the game runs as usual and hit detection does not move a hair,
	# and you can see that gameplay really talks to the visual through the interface (facing / pose / aim / hit / blink).
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	c.move_speed = 0.0
	c.bullet_scene = null # Do not let it fire: one hit would knock the player back, and they could not lie down afterwards
	c.max_health = 100
	c.health = 100
	c.global_position = Vector2(600, 304)
	player.global_position = Vector2(480, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	# Note the hit points (offsets relative to the body) before changing skins
	var player_muzzle := player._muzzle_position(Vector2.RIGHT) - player.global_position
	var enemy_muzzle := c.level_muzzle_position() - c.global_position

	var stub := load("res://tests/stub_appearance.gd")
	player.get_node("Visual").set_script(stub)
	c.get_node("Visual").set_script(stub)
	await frames(2)

	check("judgement points are unchanged: player", player._muzzle_position(Vector2.RIGHT) - player.global_position == player_muzzle,
		str(player._muzzle_position(Vector2.RIGHT) - player.global_position))
	check("judgement points are unchanged: enemy", c.level_muzzle_position() - c.global_position == enemy_muzzle,
		str(c.level_muzzle_position() - c.global_position))

	# Play as usual: walk, shoot an enemy, lie down, take a hit
	Input.action_press("move_right")
	await frames(6)
	Input.action_release("move_right")
	check("still moves", player.global_position.x > 480.0, str(player.global_position.x))
	player._shoot(Vector2.RIGHT)
	for i in 40:
		await frames(1)
		if c.health < 10:
			break
	check("still shoots and hits", c.health < 100, str(c.health))
	Input.action_press("crouch")
	await frames(6)
	check("still lies down", player.is_crouching and (player._shape.shape as RectangleShape2D).size.y == Player.CROUCH_HEIGHT)
	Input.action_release("crouch")
	await frames(6)
	player.take_damage(HIT)
	await frames(2)
	check("still takes damage", player.health < player.max_health, str(player.health))

	# Run through the enemy side too: lie down, turn around
	c.set_prone(true)
	c.facing = -c.facing
	c._apply_visual_facing()
	await frames(2)

	var player_calls: Array = player.get_node("Visual").calls
	var enemy_calls: Array = c.get_node("Visual").calls
	for call_name in ["face", "aim", "pose", "kick", "blink"]:
		check("the player's logic calls appearance.%s()" % call_name, player_calls.has(call_name), str(player_calls))
	for call_name in ["face", "aim", "pose", "flash_hit"]:
		check("the enemy's logic calls appearance.%s()" % call_name, enemy_calls.has(call_name), str(enemy_calls))
	release_all_input()
