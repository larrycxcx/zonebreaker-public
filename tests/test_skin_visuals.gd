extends GameTest
## 素材包的外观部分：角色外观和特效都能整包替换，而且**只换外观、不改规则**。
## 音效那半边在 test_audio.gd 里。

const STUB := "res://tests/stub_appearance.gd"


## 现做一个素材包：appearances / effects 里填什么由参数决定，其余都回落到默认包。
func make_skin(appearances := {}, effects := {}) -> SkinPack:
	var skin := SkinPack.new()
	skin.display_name = "测试皮肤"
	skin.fallback = Skins.default_skin()
	for key in appearances:
		skin.appearances[key] = appearances[key]
	for key in effects:
		skin.effects[key] = effects[key]
	return skin


## 把一个脚本打包成场景（当外观或特效用）。
func scene_of(script_path: String) -> PackedScene:
	var node := Node2D.new()
	node.set_script(load(script_path))
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


func test_keys_cover_everyone() -> void:
	# 关卡里每个角色都要有皮肤键，而且键都在清单里（做素材的人照清单准备）
	await reset_scene(true)
	var actors: Array[Node] = [player]
	actors.append_array(enemies())
	# 每个角色用的是哪个键要对得上，不能漏填（漏填会退回基类默认的 walker，画面上看不出来）
	var expected := {
		"Player": PlayerProgress.DEFAULT_LOOK, "WalkerA": &"1_a", "WalkerB": &"1_b", "WalkerC": &"1_c",
		"WalkerF": &"1_f", "Turret1": &"1_g", "Turret2": &"1_g",
		"FlyerE": &"1_e", "ChaserD": &"1_d", "BossMissile": &"1_boss",
	}
	for actor in actors:
		var key: StringName = actor.get(&"skin_key")
		check("%s uses the %s skin" % [actor.name, expected.get(String(actor.name), "?")],
			key == expected.get(String(actor.name)), str(key))


func test_the_key_list_is_a_readme_not_a_whitelist() -> void:
	if needs_art(): return
	# `APPEARANCE_KEYS` 是给做素材的人看的说明。**不能拿它当白名单**：
	# 23 关各有各的敌人和 Boss，新键会一直加，当白名单的话「加一种敌人」就得改常量，DLC 更是改不到。
	# 要守的是反过来那条：**包里填的每一个键，都得真能画出东西来**。
	var pack := load("res://skins/cyberpunk/cyberpunk_skin.tres") as SkinPack
	for key: StringName in pack.appearances:
		var scene: PackedScene = pack.appearances[key]
		check("%s brings a scene" % key, scene != null)
		var made := scene.instantiate() if scene != null else null
		check("%s's scene really is an Appearance" % key, made is Appearance, str(made))
		if made != null:
			made.free()
	# 现场造一个表里没有的键，照样装得上——以后加新敌人不用回来改常量
	var invented := SkinPack.new()
	invented.fallback = Skins.default_skin()
	invented.appearances = {&"zone_09_sniper": pack.appearances.get(&"1_a")}
	check("a key nobody listed still resolves", invented.find_appearance(&"zone_09_sniper") != null)


func test_default_skin_leaves_the_built_in_art_alone() -> void:
	await reset_scene(true)
	check("the default pack ships no appearance overrides", Skins.default_skin().appearances.is_empty())
	check("and no effect overrides", Skins.default_skin().effects.is_empty())
	check("so characters keep the art from their own scene", player.get_node("Visual") is Appearance)


func test_a_skin_replaces_a_character_s_appearance() -> void:
	# 换上只提供「玩家外观」的包：玩家换皮，敌人保持原样
	await reset_scene(true, false, make_skin({PlayerProgress.DEFAULT_LOOK: scene_of(STUB)}))
	keep_only_enemies(["WalkerA"])
	await frames(5)
	var skinned: Node = player.get_node("Visual")
	check("the player got the skin's appearance", skinned.get_script().resource_path == STUB, str(skinned.get_script()))
	check("it is still called Visual and sits on the player", skinned.get_parent() == player)
	check("the enemy kept its own", main.get_node("Enemies/WalkerA/Visual").get_script().resource_path != STUB)
	# 换皮之后照样能玩，判定一点不变
	var muzzle := player._muzzle_position(Vector2.RIGHT) - player.global_position
	check("judgement points unchanged", muzzle == Player.LEVEL_MUZZLE, str(muzzle))
	Input.action_press("move_right")
	await frames(6)
	release_all_input()
	check("still moves", player.global_position.x > 64.0)
	check("and the logic drives it through the interface", (skinned.calls as Array).has("face"), str(skinned.calls))


func test_a_skin_replaces_an_effect() -> void:
	# 换上只提供「枪口闪光」的包
	await reset_scene(false, false, make_skin({}, {&"muzzle_flash": scene_of(STUB)}))
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	player._shoot(Vector2.RIGHT)
	await frames(1)
	var fx: Fx = main.get_node("Fx")
	var effects := fx.get_children()
	check("the flash came from the skin", not effects.is_empty() and effects[0].get_script().resource_path == STUB,
		str(effects.map(func(e): return e.get_script())))


func test_missing_entries_fall_back() -> void:
	# 包里没填的东西一律回落：外观用角色场景自带的，特效用 Fx 上配的默认场景
	await reset_scene(false, false, make_skin())
	player.global_position = Vector2(400, 304)
	await frames(10)
	check("appearance falls back to the built-in one", player.get_node("Visual").get_script().resource_path.ends_with("appearance.gd"))
	player._shoot(Vector2.RIGHT)
	await frames(1)
	var fx: Fx = main.get_node("Fx")
	check("effects fall back to the Fx defaults", not fx.get_children().is_empty())


func test_a_broken_skin_does_not_break_the_game() -> void:
	# 皮肤包把外观填成了一个普通场景（根节点没有 Appearance 脚本）：退回默认外观，游戏照常跑
	var not_an_appearance := PackedScene.new()
	var node := Node2D.new()
	not_an_appearance.pack(node)
	node.free()
	await reset_scene(false, false, make_skin({PlayerProgress.DEFAULT_LOOK: not_an_appearance}))
	await frames(10)
	check("kept the built-in appearance", player.get_node("Visual") is Appearance)
	Input.action_press("move_right")
	await frames(6)
	release_all_input()
	check("and the game still runs", player.global_position.x > 64.0)


func test_appearances_fall_back_through_the_chain() -> void:
	# 包 A 提供玩家外观，包 B 自己什么都没有、fallback 指向 A：用 B 也要拿到 A 的外观
	var pack_a := make_skin({PlayerProgress.DEFAULT_LOOK: scene_of(STUB)})
	var pack_b := make_skin()
	pack_b.fallback = pack_a
	await reset_scene(false, false, pack_b)
	await frames(5)
	check("the appearance came from the fallback pack", player.get_node("Visual").get_script().resource_path == STUB,
		str(player.get_node("Visual").get_script()))


func test_the_explosion_is_drawn_by_the_fx_layer() -> void:
	# 手雷自己不画爆炸，只报告事件；画面归 Fx（所以也能被素材包替换）
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	var grenade: Grenade = load("res://scenes/grenade.tscn").instantiate()
	main.add_child(grenade)
	grenade.global_position = Vector2(460, 300)
	await frames(2)
	var fx: Fx = main.get_node("Fx")
	for effect in fx.get_children():
		effect.free()
	# 故意改成和特效场景默认值（56）不同的半径，否则「没按半径缩放」也看不出来
	grenade.blast_radius = 80.0
	var radius := grenade.blast_radius # 爆炸之后它自己就释放了，先记下来
	grenade.explode()
	await frames(2)
	var blasts := fx.get_children().filter(func(e): return e.get("radius") != null)
	check("an explosion effect appears", not blasts.is_empty(), str(fx.get_children()))
	if not blasts.is_empty():
		check("sized by the grenade's blast radius", blasts[0].radius == radius,
			"%s vs %s" % [blasts[0].radius, radius])
		check("drawn where it went off", blasts[0].global_position.distance_to(Vector2(460, 300)) < 4.0,
			str(blasts[0].global_position))



## 第三方素材包的目录：只有这几个包自己（和 `scenes/skins/` 里它们的外观场景）可以直接引用里面的文件。
const THIRD_PARTY_PACKS := ["res://skins/cyberpunk/", "res://skins/industrial/",
	"res://skins/bar_street/", "res://skins/basement/"]


func test_nothing_outside_the_packs_hard_links_their_art() -> void:
	# 公开版去掉了第三方素材（`tools/export_public.py`）。一个 `.tres` / `.tscn` 只要用 ext_resource
	# 引用了缺的文件，**整个就加载不了**：步枪的 `.tres` 因为图标缺了读不出来，玩家连枪都拿不到。
	# 所以素材包以外的地方一律存路径（`icon_path`、`skin_path`、`texture_path`、`atlas_path`），用的时候文件在才加载。
	var offenders: Array[String] = []
	var scanned := [0]
	_scan_for_hard_links("res://", offenders, scanned)
	check("setup: scanned the project's scenes and resources", scanned[0] > 60, str(scanned[0]))
	check("no scene or resource outside the packs hard-links their art", offenders.is_empty(),
		", ".join(offenders.slice(0, 5)))


func _scan_for_hard_links(dir: String, offenders: Array[String], scanned: Array) -> void:
	if dir in THIRD_PARTY_PACKS or dir == "res://scenes/skins/" or dir.begins_with("res://."):
		return
	for sub in DirAccess.get_directories_at(dir):
		_scan_for_hard_links(dir + sub + "/", offenders, scanned)
	for file in DirAccess.get_files_at(dir):
		if not (file.ends_with(".tscn") or file.ends_with(".tres")):
			continue
		# 像素图工具的预览（`tools/map_paint.py preview`）：本地生成、不进仓库（.gitignore）
		if dir + file == "res://scenes/map_preview.tscn":
			continue
		scanned[0] += 1
		for line in FileAccess.get_file_as_string(dir + file).split("\n"):
			if not line.begins_with("[ext_resource"):
				continue
			for pack: String in THIRD_PARTY_PACKS:
				if pack in line:
					offenders.append(dir + file)
