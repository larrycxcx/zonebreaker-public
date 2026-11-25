extends GameTest
## Enemy F (`enemy_walker_f.tscn` / `EnemyGrenadier`): a kind of patroller that does not shoot and only throws grenades.
## The grenade rules are exactly the player's; the only difference is who they hit: its grenades hurt the player, not enemies, and cannot hurt itself.
## No chasing, no jumping, no going prone.

const PLAYER_GRENADE := "res://scenes/grenade.tscn"
const ENEMY_GRENADE := "res://scenes/enemy_grenade.tscn"

var f: EnemyGrenadier


## Keep only F, on the empty stretch at the right end of the stage (x 1060..640: no platforms overhead, so the arc never lands on a platform halfway,
## and clear of the solid CrawlBlock). In the stage it stands on Platform3; flat ground is easier to control for behaviour tests.
func start(x := 1060.0, player_x := 1260.0) -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerF"])
	f = main.get_node("Enemies/WalkerF")
	f.global_position = Vector2(x, 306)
	f.velocity = Vector2.ZERO
	f.facing = 1
	f._apply_facing()
	f._throw_timer = 0.0 # It is on screen when the stage loads and may already have thrown one: do not carry that cooldown in
	for grenade in tree.get_nodes_in_group(Grenade.GROUP):
		grenade.free() # and do not count that grenade either
	player.health = 999
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	snap_camera()
	await frames(5)


## Every grenade in play. Found by group rather than only main's direct children:
## enemy grenades hang under Enemies like enemy bullets (so they finish their flight after the enemy dies).
func grenades() -> Array:
	return tree.get_nodes_in_group(Grenade.GROUP).filter(func(g): return is_instance_valid(g))


## Wait for it to throw a grenade and return it; null on timeout.
func wait_for_throw(limit := 480) -> Grenade:
	for i in limit:
		await frames(1)
		var thrown := grenades()
		if not thrown.is_empty():
			return thrown[0]
	return null


## Watch for some frames and return true if a grenade ever appeared (grenades explode and vanish, so counting afterwards finds nothing).
func threw_anything(frame_count := 150) -> bool:
	for i in frame_count:
		await frames(1)
		if not grenades().is_empty():
			return true
	return false


## Pin the player in place (otherwise the blast knocks them back and every following assertion goes wrong).
func pin_player(x: float, frame_count: int) -> void:
	for i in frame_count:
		player.global_position = Vector2(x, 304)
		player.velocity = Vector2.ZERO
		await frames(1)


func test_config() -> void:
	await start()
	# Check with a Node variable: writing f is Boss directly does not compile, since the static types can never match
	var node: Node = f
	check("F is a normal enemy, not a boss", f is Enemy and not (node is Boss))
	check("F patrols like the other walkers", f is EnemyWalker)
	check("F never shoots", f.bullet_scene == null)
	check("F never lies down", not f.can_go_prone)
	check("F throws enemy grenades", f.grenade_scene != null)


func test_grenade_rules_match_the_players() -> void:
	# "Same rules as the player's grenade": apart from who it hits (target_layer) and the colour, the exported values must be exactly the same.
	# Damage counts in each target's units: the player's hits enemies (one bullet SHOT), F's hits the player (one HIT), both 3 at the centre and 1 at the edge
	await reset_scene()
	var mine: Grenade = load(PLAYER_GRENADE).instantiate()
	var theirs: Grenade = load(ENEMY_GRENADE).instantiate()
	for field in ["throw_speed", "lift", "gravity", "bounciness", "bounces", "fuse", "blast_radius"]:
		check("same %s as the player's grenade" % field, mine.get(field) == theirs.get(field),
			"%s vs %s" % [mine.get(field), theirs.get(field)])
	for field in ["max_damage", "min_damage"]:
		check("same %s in its target's units" % field, mine.get(field) / SHOT == theirs.get(field) / HIT
			and mine.get(field) % SHOT == 0 and theirs.get(field) % HIT == 0, "%s vs %s" % [mine.get(field), theirs.get(field)])
	check("the player's grenade hits enemies", mine.target_layer == 8, str(mine.target_layer))
	check("the enemy's grenade hits the player", theirs.target_layer == 2, str(theirs.target_layer))
	mine.free()
	theirs.free()


func test_patrols_without_jumping() -> void:
	await start(520, 1000) # The player out of range so it does not get busy throwing grenades; walking right a few steps F runs into the CrawlBlock and turns around
	var moved := false
	var airborne := false
	var turned := false
	var first := f.facing
	for i in 300:
		await frames(1)
		moved = moved or absf(f.velocity.x) > 0.0
		airborne = airborne or not f.is_on_floor()
		turned = turned or f.facing != first
	check("patrols", moved)
	check("turns around at the edges like other walkers", turned)
	check("never jumps", not airborne)


func test_throws_at_a_player_in_front() -> void:
	await start()
	var grenade := await wait_for_throw()
	check("throws a grenade at the player in front", grenade != null)
	if grenade != null:
		check("it is an enemy grenade", grenade.target_layer == 2, str(grenade.target_layer))
		check("thrown forward", grenade.velocity.x > 0.0, str(grenade.velocity))
		check("thrown in an arc, like the player's", grenade.velocity.y < 0.0, str(grenade.velocity))


func test_does_not_throw_backwards_or_out_of_range() -> void:
	# A player behind it: it does not turn around and does not throw
	await start(1060, 860)
	f.facing = 1
	f._apply_facing()
	f.move_speed = 0.0
	check("no grenade at a player behind it", not await threw_anything())
	# Too far and off screen itself: cannot see, does not throw
	await start(300, 1100)
	f.move_speed = 0.0
	check("setup: F is off screen", not f.is_partly_on_screen())
	check("no grenade at a far player it cannot see", not await threw_anything())
	# On screen it throws even when too far (the grenade lands halfway, blocking the way): it has to react when the player can see it
	# The player hugs the left of the stage and the camera rests on the left limit: F 400px away is still on screen
	await start(500, 100)
	f.facing = -1
	f._apply_facing()
	f.move_speed = 0.0
	check("setup: F is on screen and out of reach", f.is_partly_on_screen() and 400.0 > f.max_throw_distance)
	check("on screen, a far player still gets a grenade", await threw_anything())
	# Face to face: the grenade would overshoot, so it does not throw either
	await start(300, 300 + f.min_throw_distance - 40.0)
	f.move_speed = 0.0
	check("no grenade at a player right in its face", not await threw_anything())


func test_does_not_throw_at_a_player_it_cannot_see() -> void:
	# A wall in between: cannot see, does not throw (the same line-of-sight rule as patrollers firing)
	await start()
	f.move_speed = 0.0
	add_wall(1160, 72)
	# It threw one before the wall went up (the cooldown starts at 0); clear it, then look
	for g in grenades():
		g.free()
	f._throw_timer = 0.0
	await frames(2)
	check("setup: the wall blocks its line of sight", f.throw_target() == null)
	check("holds the grenade when it cannot see the player", not await threw_anything())
	# Control group: take the wall away and it throws right away from the same spot
	main.get_node("Level/Walls/TestWall").free()
	await frames(2)
	check("throws as soon as the wall is gone", await threw_anything())


func test_its_grenade_hurts_the_player() -> void:
	await start()
	player.health = 3
	f.move_speed = 0.0
	var grenade := await wait_for_throw()
	check("setup: thrown", grenade != null)
	for i in 180:
		await frames(1)
		player.global_position = Vector2(1260, 304) # Pin them so they really take the blast
		player.velocity = Vector2.ZERO
		if not is_instance_valid(grenade):
			break
	check("the grenade hurts the player", player.health < 3, str(player.health))


func test_its_grenade_spares_enemies_and_itself() -> void:
	await start()
	f.move_speed = 0.0
	# Put an ally near the landing point and see whether it gets hit
	var mate: Enemy = load("res://scenes/enemy_1_a.tscn").instantiate()
	main.get_node("Enemies").add_child(mate)
	mate.global_position = Vector2(1244, 304)
	mate.move_speed = 0.0
	await frames(5)
	var mate_health := mate.health
	var f_health := f.health
	var grenade := await wait_for_throw()
	check("setup: thrown", grenade != null)
	await pin_player(1260, 360)
	check("its own grenade does not hurt the thrower", f.health == f_health, str(f.health))
	check("and does not hurt other enemies", is_instance_valid(mate) and mate.health == mate_health,
		str(mate.health) if is_instance_valid(mate) else "dead")
	check("the player did take the hit", player.health < 999, str(player.health))


func test_who_each_grenade_can_hurt() -> void:
	# The two kinds of grenade differ only in "who they hit": set off a player grenade next to F and it loses health; set off an enemy grenade and it is unharmed.
	# (The whole arc of a player's throw is tested in test_grenade.gd; this only looks at who takes the damage.)
	await start()
	f.move_speed = 0.0
	f.max_health = 100 # Raise its health a bit so one grenade does not kill it, letting both kinds be tried
	f.health = 100
	for path in [PLAYER_GRENADE, ENEMY_GRENADE]:
		var before := f.health
		var grenade: Grenade = load(path).instantiate()
		main.add_child(grenade)
		grenade.global_position = f.global_position + Vector2(20, 0)
		grenade.explode()
		await frames(2)
		var hurt: bool = not is_instance_valid(f) or f.health < before
		if path == PLAYER_GRENADE:
			check("the player's grenade hurts F", hurt, str(f.health) if is_instance_valid(f) else "dead")
		else:
			check("an enemy grenade does not hurt F", not hurt, str(f.health) if is_instance_valid(f) else "dead")


func test_never_lies_down_or_jumps_for_a_crouching_player() -> void:
	await start()
	Input.action_press("crouch")
	var prone := false
	var airborne := false
	for i in 180:
		await frames(1)
		prone = prone or f.is_prone
		airborne = airborne or not f.is_on_floor()
	Input.action_release("crouch")
	check("never lies down", not prone)
	check("never jumps", not airborne)
