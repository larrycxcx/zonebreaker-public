extends GameTest
## The cyberpunk skin pack's HUD (SpriteHud, sprites generated from the GUI art pack by tools/hud_build.py).
##
## The HUD itself (hud.gd) works out what to show as usual and the pack's appearance only draws: this guards "the state the appearance gets matches gameplay" —
## one cell per point of health, stamina proportional with a colour change when too tired to run, the weapon slot showing the gun in hand, ultimate charges, the boss bar proportional shrinking right to left,
## plus how the bars are cut, display only (never takes the mouse), the default pack still on placeholder blocks, and the placeholder blocks updating but not drawn.

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func look() -> SpriteHud:
	return main.get_node("HUD").look() as SpriteHud


# ---------------------------------------------------------------- How it is cut

func test_bar_pieces_are_end_middle_end() -> void:
	check("one segment uses the rounded single piece", SpriteHud.piece(0, 1) == 3)
	check("three segments: left, middle, right", [SpriteHud.piece(0, 3), SpriteHud.piece(1, 3), SpriteHud.piece(2, 3)] == [0, 1, 2])
	check("five segments keep middles in the middle",
		[SpriteHud.piece(0, 5), SpriteHud.piece(2, 5), SpriteHud.piece(4, 5)] == [0, 1, 2])


func test_filled_cuts_the_bar_where_the_fill_ends() -> void:
	check("empty bar has no filled parts", SpriteHud.filled(3, 32, 0, 0).is_empty())
	check("two of three full", SpriteHud.filled(3, 32, 0, 64) == [[0, 0, 32], [1, 0, 32]], str(SpriteHud.filled(3, 32, 0, 64)))
	check("a fill ending mid-piece cuts that piece", SpriteHud.filled(4, 16, 0, 40) == [[0, 0, 16], [1, 0, 16], [2, 0, 8]],
		str(SpriteHud.filled(4, 16, 0, 40)))
	check("a fill hugging the right end", SpriteHud.filled(4, 32, 80, 128) == [[2, 16, 16], [3, 0, 32]],
		str(SpriteHud.filled(4, 32, 80, 128)))


# ---------------------------------------------------------------- Once plugged in

func test_the_skin_draws_the_hud_and_the_default_does_not() -> void:
	if needs_art(): return
	await reset_scene()
	check("the default pack keeps the placeholder HUD", main.get_node("HUD").look() == null)
	check("and its blocks are drawn", main.get_node("HUD/HealthBar").modulate.a == 1.0)
	await reset_scene(false, false, skin())
	check("the skin puts its HUD look in", look() != null)
	for path in ["HUD/HealthBar", "HUD/StaminaBar", "HUD/WeaponIcon", "HUD/UltimateRow", "HUD/BossBar"]:
		check("%s is no longer drawn" % path, (main.get_node(path) as CanvasItem).modulate.a == 0.0)
	# The placeholder blocks keep updating: logic and old tests read them
	check("but the placeholders still update", (main.get_node("HUD/HealthBar/Fill") as ColorRect).size.x > 0.0)


func test_health_is_one_segment_per_point() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	check("full health at the start", look().health == player.max_health and look().max_health == player.max_health,
		"%d / %d" % [look().health, look().max_health])
	player.take_damage(HIT)
	await frames(1)
	check("losing a hit takes a third of the bar", look().health == player.max_health - HIT
		and absf(look().health_fill() - SpriteHud.HEALTH_PIECE.x * look().health_segments * 2.0 / 3.0) <= 1.0, str(look().health_fill()))


func test_stamina_follows_the_player_and_turns_orange_when_spent() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	player._set_stamina(player.max_stamina * 0.5)
	await frames(1)
	check("half stamina, half the bar", absf(look().stamina_ratio - 0.5) < 0.02, str(look().stamina_ratio))
	check("half the bar in pixels", look().stamina_fill() == 32, str(look().stamina_fill()))
	check("not tired yet", not look().tired)
	# Really run out: lower the stamina first, hold run going right until "exhausted", and it stays orange until back at the threshold
	player._set_stamina(8.0)
	Input.action_press("move_right")
	Input.action_press("sprint")
	for i in 60:
		await frames(1)
		if player.is_exhausted():
			break
	release_all_input()
	await frames(1)
	check("setup: the player ran out of stamina", player.is_exhausted())
	check("spent: the bar turns orange", look().tired)


func test_the_weapon_slot_shows_the_gun_in_hand() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	check("the rifle at the start", look().weapon_look == &"rifle" and look().weapon_texture() != null
		and look().weapon_texture() == look().weapon_icons[&"rifle"], str(look().weapon_look))
	player.switch_weapon()
	await frames(1)
	check("switching shows the launcher", look().weapon_look == &"launcher"
		and look().weapon_texture() == look().weapon_icons[&"launcher"], str(look().weapon_look))
	for weapon in player.weapons:
		check("every weapon the player carries has an icon (%s)" % weapon.look, look().weapon_icons.has(weapon.look))


func test_the_ultimate_count_follows_its_ammo() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	check("both charges at the start", look().ultimate_ammo == player.ultimate_ammo() and look().ultimate_max == player.ultimate_weapon.max_ammo,
		"%d / %d" % [look().ultimate_ammo, look().ultimate_max])
	Input.action_press("ultimate")
	await frames(2)
	Input.action_release("ultimate")
	await frames(2)
	check("using one leaves one", look().ultimate_ammo == player.ultimate_ammo() and look().ultimate_ammo == look().ultimate_max - 1,
		str(look().ultimate_ammo))
	check("the charges are drawn as bombs", look().ultimate_icon != null
		and look().ultimate_icon.get_height() <= (look().get_node("WeaponSlot") as Control).size.y,
		str(look().ultimate_icon))
	tree.paused = false


func test_the_boss_bar_appears_and_drains_from_the_right() -> void:
	if needs_art(): return
	await reset_scene(true, false, skin())
	keep_only_enemies(["BossMissile"])
	var boss: BossMissile = main.get_node("Enemies/BossMissile")
	check("no boss bar before it appears", not look().boss_visible())
	boss.appear()
	await frames(1)
	check("the boss bar shows when it appears", look().boss_visible())
	check("with the skin's portrait", (look().get_node("BossPanel/Portrait") as TextureRect).texture == boss.hud_portrait())
	check("full at first", look().boss_fill_from() == 0, str(look().boss_fill_from()))
	boss.take_damage(boss.max_health / 2)
	await frames(1)
	check("half health: the full part starts halfway", look().boss_fill_from() == 64, str(look().boss_fill_from()))
	boss.die()
	await frames(1)
	check("gone when the boss dies", not look().boss_visible())


func test_the_hud_is_pure_display_and_on_screen() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	var controls: Array = look().find_children("*", "Control", true, false)
	controls.append(look())
	check("nothing in the HUD eats the mouse", controls.all(func(c: Control) -> bool: return c.mouse_filter == Control.MOUSE_FILTER_IGNORE))
	var screen := Rect2(Vector2.ZERO, Vector2(640, 360))
	var hud := look()
	for part in [Rect2(hud.health_at, Vector2(SpriteHud.HEALTH_PIECE.x * hud.health_segments, SpriteHud.HEALTH_PIECE.y)),
			Rect2(hud.energy_at, Vector2(SpriteHud.ENERGY_PIECE.x * hud.energy_segments, SpriteHud.ENERGY_PIECE.y)),
			Rect2(hud.boss_bar_at, Vector2(SpriteHud.HEALTH_PIECE.x * hud.boss_segments, SpriteHud.HEALTH_PIECE.y)),
			(hud.get_node("BossPanel") as Control).get_rect()]:
		check("%s is on screen" % [part], screen.encloses(part))
	check("the boss bar does not run into its portrait",
		hud.boss_bar_at.x + SpriteHud.HEALTH_PIECE.x * hud.boss_segments <= (hud.get_node("BossPanel") as Control).position.x)
