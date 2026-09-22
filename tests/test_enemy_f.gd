extends GameTest
## 敌人 F（`enemy_walker_f.tscn` / `EnemyGrenadier`）：巡逻兵的一种，不开枪只扔手雷。
## 手雷规则和玩家的完全一样，区别只有「打谁」：它的手雷炸玩家、不炸敌人，也炸不到它自己。
## 不追击、不跳跃、不趴下。

const PLAYER_GRENADE := "res://scenes/grenade.tscn"
const ENEMY_GRENADE := "res://scenes/enemy_grenade.tscn"

var f: EnemyGrenadier


## 只留 F，放到关卡右端那段空地上（x 1060..640：头顶没有平台，抛物线不会中途落在平台上，
## 也避开了 CrawlBlock 那块实心方块）。关卡里它站在 Platform3 上，测行为时平地更好控制。
func start(x := 1060.0, player_x := 1260.0) -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerF"])
	f = main.get_node("Enemies/WalkerF")
	f.global_position = Vector2(x, 306)
	f.velocity = Vector2.ZERO
	f.facing = 1
	f._apply_facing()
	player.health = 999
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	await frames(5)


## 场上所有手雷。按组找而不是只看 main 的直接子节点：
## 敌人的手雷和敌人子弹一样挂在 Enemies 下面（这样敌人死了手雷还会飞完）。
func grenades() -> Array:
	return tree.get_nodes_in_group(Grenade.GROUP).filter(func(g): return is_instance_valid(g))


## 等它扔出一颗手雷，返回那颗；超时返回 null。
func wait_for_throw(limit := 480) -> Grenade:
	for i in limit:
		await frames(1)
		var thrown := grenades()
		if not thrown.is_empty():
			return thrown[0]
	return null


## 盯着若干帧，只要出现过手雷就返回 true（手雷会爆炸消失，事后再数是数不到的）。
func threw_anything(frame_count := 150) -> bool:
	for i in frame_count:
		await frames(1)
		if not grenades().is_empty():
			return true
	return false


## 把玩家钉在原地（否则会被爆炸击退，后面的断言全乱）。
func pin_player(x: float, frame_count: int) -> void:
	for i in frame_count:
		player.global_position = Vector2(x, 304)
		player.velocity = Vector2.ZERO
		await frames(1)


func test_config() -> void:
	await start()
	# 用 Node 变量来判断：直接写 f is Boss 会因为静态类型不可能匹配而编译不过
	var node: Node = f
	check("F is a normal enemy, not a boss", f is Enemy and not (node is Boss))
	check("F patrols like the other walkers", f is EnemyWalker)
	check("F never shoots", f.bullet_scene == null)
	check("F never lies down", not f.can_go_prone)
	check("F throws enemy grenades", f.grenade_scene != null)


func test_grenade_rules_match_the_players() -> void:
	# 「规则和玩家手雷一样」：除了打谁（target_layer）和颜色，导出的数值必须完全一致。
	# 伤害按各自目标的单位算：玩家的打敌人（一发子弹 SHOT），F 的打玩家（一下 HIT），都是中心 3 下、边缘 1 下
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
	await start(520, 1000) # 玩家在射程外，免得它忙着扔手雷；F 朝右走几步就会撞上 CrawlBlock 掉头
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
	# 背后的玩家：不回头，也不扔
	await start(1060, 860)
	f.facing = 1
	f._apply_facing()
	f.move_speed = 0.0
	check("no grenade at a player behind it", not await threw_anything())
	# 太远
	await start(300, 300 + f.max_throw_distance + 120.0)
	f.move_speed = 0.0
	check("no grenade at a player out of reach", not await threw_anything())
	# 贴脸：手雷会扔过头，所以也不扔
	await start(300, 300 + f.min_throw_distance - 40.0)
	f.move_speed = 0.0
	check("no grenade at a player right in its face", not await threw_anything())


func test_does_not_throw_at_a_player_it_cannot_see() -> void:
	# 中间隔一堵墙：看不见就不扔（和巡逻兵开枪同一套视线规则）
	await start()
	f.move_speed = 0.0
	add_wall(1160, 72)
	# 挡墙之前它已经扔过一颗（冷却从 0 开始），清掉再看
	for g in grenades():
		g.free()
	f._throw_timer = 0.0
	await frames(2)
	check("setup: the wall blocks its line of sight", f.throw_target() == null)
	check("holds the grenade when it cannot see the player", not await threw_anything())
	# 对照组：拆掉墙，同一位置马上就扔
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
		player.global_position = Vector2(1260, 304) # 钉住，让它真的挨炸
		player.velocity = Vector2.ZERO
		if not is_instance_valid(grenade):
			break
	check("the grenade hurts the player", player.health < 3, str(player.health))


func test_its_grenade_spares_enemies_and_itself() -> void:
	await start()
	f.move_speed = 0.0
	# 在落点附近放一个同伴，看它会不会被炸到
	var mate: Enemy = load("res://scenes/enemy_walker_a.tscn").instantiate()
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
	# 两边的手雷只差「打谁」：在 F 旁边引爆一颗玩家的手雷，它掉血；引爆一颗敌人的手雷，它毫发无伤。
	# （玩家扔出去的整条抛物线在 test_grenade.gd 里测过，这里只看伤害归属。）
	await start()
	f.move_speed = 0.0
	f.max_health = 100 # 血调高一点，一颗手雷炸不死，两种手雷才都试得成
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
