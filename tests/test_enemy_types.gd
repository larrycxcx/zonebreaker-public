extends GameTest
## Enemy types: A (single shot, 220px, standing only), B (bursts of 4~6, 220px, standing only),
## C (single shot, 400px, goes prone after the player), and the turret (400px, 12 health).


## With the player parked here every enemy is out of range (the enemy set up is at x=900, the longest range is 400).
const PARKED_X := 80.0


## Fix a patroller standing at x=900 facing left, no longer walking. The player waits out of range first:
## if it were in range during setup, the enemy would fire once on the default cooldown, hiding the rhythm the test changes afterwards.
func _setup_duel(enemy_name: String) -> Enemy:
	await reset_scene(true)
	keep_only_enemies([enemy_name])
	var enemy: Enemy = main.get_node("Enemies/" + enemy_name)
	player.global_position = Vector2(PARKED_X, 304)
	await frames(5)
	enemy.global_position = Vector2(900, 304)
	enemy.facing = -1
	enemy._visual.scale.x = -1
	if enemy is EnemyWalker:
		(enemy as EnemyWalker).move_speed = 0.0
		(enemy as EnemyWalker)._apply_facing()
	await frames(2)
	# Enemies fire when on screen: before being moved it may have fired from where it was; do not carry that cooldown into the observation window
	enemy._fire_timer = 0.0
	enemy._burst_left = 0
	return enemy


## The player stands distance in front of the enemy. The player is made invincible so being knocked back or killed does not interrupt the observation.
func _step_in_front(enemy: Enemy, distance: float) -> void:
	player.global_position = Vector2(enemy.global_position.x - distance, 304)
	player.velocity = Vector2.ZERO


## The player stands distance in front of the enemy for frame_count frames, recording which frame each bullet was fired on,
## then splits them into bursts by gap (9~10 frames between shots of a burst, fire_interval between bursts).
## After observing, move the player away and wait a little so the last burst finishes instead of being cut off as "1 shot".
func _observe_bursts(enemy: Enemy, distance: float, frame_count: int) -> Array:
	var shot_frames := []
	var frame := [0]
	enemy.shot_fired.connect(func(): shot_frames.append(frame[0]))
	_step_in_front(enemy, distance)
	for i in frame_count + 40:
		if i == frame_count:
			player.global_position = Vector2(PARKED_X, 304)
		player._invincible_timer = 1000.0
		await tree.physics_frame
		frame[0] += 1
	var bursts := []
	var last := -2000
	for f in shot_frames:
		if f - last > 15:
			bursts.append(0)
		bursts[-1] += 1
		last = f
	return bursts


func test_types_are_configured() -> void:
	await reset_scene(true)
	var a: Enemy = main.get_node("Enemies/WalkerA")
	var b: Enemy = main.get_node("Enemies/WalkerB")
	var c: Enemy = main.get_node("Enemies/WalkerC")
	var turret: Enemy = main.get_node("Enemies/Turret1")
	check("A, B and C are all patrolling walkers", a is EnemyWalker and b is EnemyWalker and c is EnemyWalker)
	check("A: 220px range, single shots, standing only", a.detect_range == 220.0 and a.burst_min == 1 and a.burst_max == 1 and not a.can_go_prone)
	check("B: 220px range, bursts of 2-3, standing only", b.detect_range == 220.0 and b.burst_min == 2 and b.burst_max == 3 and not b.can_go_prone)
	check("C: 400px range, single shots, can go prone", c.detect_range == 400.0 and c.burst_min == 1 and c.burst_max == 1 and c.can_go_prone)
	check("walkers take 2 shots", a.max_health == 2 * SHOT and b.max_health == 2 * SHOT and c.max_health == 2 * SHOT)
	check("turret: 400px range and 6 shots", turret.detect_range == 400.0 and turret.max_health == 6 * SHOT, "%s / %s" % [turret.detect_range, turret.max_health])
	var colors := [a, b, c].map(func(e): return (e.get_node("Visual/Body") as ColorRect).color)
	check("A, B and C look different", colors[0] != colors[1] and colors[1] != colors[2] and colors[0] != colors[2], str(colors))


func test_type_a_fires_single_shots() -> void:
	var a := await _setup_duel("WalkerA")
	a.fire_interval = 0.5
	var bursts := await _observe_bursts(a, 60.0, 150)
	check("A fired several times", bursts.size() >= 4, str(bursts))
	check("every A volley is a single shot", bursts.all(func(n): return n == 1), str(bursts))


func test_type_b_fires_bursts_of_two_or_three() -> void:
	# The burst size is random; a fixed seed makes the result repeatable.
	seed(40521836)
	var b := await _setup_duel("WalkerB")
	b.fire_interval = 0.6
	var bursts := await _observe_bursts(b, 60.0, 420)
	check("B fired several volleys", bursts.size() >= 8, str(bursts))
	check("every B volley has 2 or 3 shots", bursts.all(func(n): return n == 2 or n == 3), str(bursts))
	check("both 2-shot and 3-shot volleys happen", bursts.has(2) and bursts.has(3), str(bursts))


func test_type_b_burst_shots_are_spaced_out() -> void:
	seed(1)
	var b := await _setup_duel("WalkerB")
	var shot_frames := []
	var frame := [0]
	b.shot_fired.connect(func(): shot_frames.append(frame[0]))
	_step_in_front(b, 120.0)
	for i in 40:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		frame[0] += 1
	check("a burst fired at least two shots", shot_frames.size() >= 2, str(shot_frames))
	if shot_frames.size() >= 2:
		var gap: int = shot_frames[1] - shot_frames[0]
		check("burst shots come 0.15s apart", gap >= 8 and gap <= 10, "%d frames" % gap)


func test_burst_finishes_even_if_the_player_leaves() -> void:
	seed(14)
	var b := await _setup_duel("WalkerB")
	var shots := [0]
	b.shot_fired.connect(func(): shots[0] += 1)
	_step_in_front(b, 120.0)
	for i in 5:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if shots[0] > 0:
			break
	check("the burst started as soon as the player stepped in", shots[0] == 1, str(shots[0]))
	# After the first shot the player runs out of range at once, and the burst still has to finish.
	player.global_position = Vector2(PARKED_X, 304)
	await frames(40)
	check("the rest of the burst still comes out", shots[0] == 2 or shots[0] == 3, str(shots[0]))


func test_only_type_c_goes_prone() -> void:
	for enemy_name in ["WalkerA", "WalkerB", "WalkerC"]:
		var enemy := await _setup_duel(enemy_name)
		_step_in_front(enemy, 120.0)
		Input.action_press("crouch")
		var ever_prone := false
		for i in 60:
			player._invincible_timer = 1000.0
			await tree.physics_frame
			ever_prone = ever_prone or enemy.is_prone
		var expected: bool = enemy_name == "WalkerC"
		check("%s %s when the player lies down" % [enemy_name, "goes prone" if expected else "stays standing"], ever_prone == expected)
		Input.action_release("crouch")


func test_type_c_outranges_a_and_b() -> void:
	# 360px: inside C's 400px range, outside A/B's 220px range.
	for enemy_name in ["WalkerA", "WalkerB", "WalkerC"]:
		var enemy := await _setup_duel(enemy_name)
		var bursts := await _observe_bursts(enemy, 360.0, 60)
		var expected: bool = enemy_name == "WalkerC"
		check("%s %s at 360px" % [enemy_name, "fires" if expected else "holds fire"], (bursts.size() > 0) == expected, str(bursts))


func test_a_and_b_fire_inside_their_range() -> void:
	for enemy_name in ["WalkerA", "WalkerB"]:
		var enemy := await _setup_duel(enemy_name)
		var bursts := await _observe_bursts(enemy, 100.0, 30)
		check("%s fires at 100px" % enemy_name, bursts.size() > 0, str(bursts))


func test_turret_range_is_200() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	await frames(5)
	turret.global_position = Vector2(1000, 304)
	var shots := [0]
	turret.shot_fired.connect(func(): shots[0] += 1)
	player.global_position = Vector2(580, 304) # 210px, out of range
	for i in 60:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("turret holds fire at 420px", shots[0] == 0, str(shots[0]))
	player.global_position = Vector2(620, 304) # 190px, in range
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("turret fires at 380px", shots[0] > 0, str(shots[0]))


func test_turret_takes_six_hits() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	turret.can_go_prone = false
	await frames(5)
	turret.global_position = Vector2(1000, 304)
	player.global_position = Vector2(880, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(3)

	# Real bullets: the first 10 do not kill it, the 12th does.
	var deaths := []
	turret.died.connect(func(): deaths.append(true))
	for i in 6:
		player._invincible_timer = 1000.0
		player.current_slot().cooldown_left = 0.0
		player._shoot(Vector2.RIGHT)
		await frames(20)
		if i == 8:
			check("five hits do not kill the turret", deaths.is_empty() and is_instance_valid(turret) and turret.health == 1, str(turret.health) if is_instance_valid(turret) else "dead")
	check("the sixth hit kills it", deaths.size() == 1)
