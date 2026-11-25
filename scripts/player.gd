class_name Player
extends CharacterBody2D
## Block player: moves left and right, jumps and shoots, with health and invincibility frames after a hit.

signal health_changed(health: int, max_health: int)
signal died
## Out of health but not truly dead yet, lying on the ground waiting for the partner to come and help (only happens in co-op).
signal downed
## Pulled back up by the partner.
signal revived
signal stamina_changed(stamina: float, max_stamina: float)
## Emitted when switching weapons (or when the current one is replaced); the HUD listens to it.
signal weapon_switched(index: int, weapon: Weapon)
## The number of ultimate charges changed; the HUD listens to it.
signal ultimate_ammo_changed(ammo: int, max_ammo: int)


@export_group("Health")
## Max health: worked out from the life stat (its own progress's stat(life)), no longer filled in by hand.
var max_health := 0
## Invincibility time after a hit, blinking and immune to all damage meanwhile.
@export var invincible_time := 1.0
## Knockback speed on a hit (horizontally away from the source of the damage).
@export var hurt_knockback := Vector2(140, -240)

@export_group("Downed")
## How long it can hold out after going down (seconds). After that it is truly dead. **This state only happens in co-op** —
## playing alone nobody can come to help, so going down would only mean waiting to die.
@export var down_time := 10.0
## Fraction of max health lost on falling into a pit.
@export var fall_damage_ratio := 1.0 / 3.0
## How long it is invincible after being brought back from a pit (enough to look around before moving).
@export var fall_grace := 1.5
## When the partner comes this close (pixels, between body origins) the downed player is pulled up automatically. No button needed.
@export var revive_range := 28.0
## Share of max health restored on revival, plus a short invincibility so the same bullet does not knock you down again right away.
@export var revive_health_ratio := 0.5
@export var revive_grace := 1.0

@export_group("Movement")
@export var move_speed := 180.0
@export var acceleration := 1400.0
@export var friction := 1800.0
@export var air_control := 0.7

@export_group("Jump")
@export var jump_velocity := -560.0
@export var gravity := 1800.0
@export var max_fall_speed := 800.0
## When the jump button is released, the upward speed is multiplied by this for a variable jump height.
@export var jump_cut := 0.5
## Time after leaving a platform edge during which you can still jump (coyote time).
@export var coyote_time := 0.1
## Time during which pressing jump just before landing still counts (jump buffer).
@export var jump_buffer_time := 0.1

@export_group("Ladder")
## Climbing speed (same up and down). A bit slower than walking: ladders are dangerous ground, and you cannot shoot while climbing.
@export var climb_speed := 100.0
## Multiplier on the jump speed when jumping sideways off a ladder (a bit lower than a standing jump, so one jump from a ladder does not reach the next layer).
@export var ladder_jump_scale := 0.6

@export_group("Crouch")
## Movement speed multiplier while prone.
@export var crouch_speed_scale := 0.6

@export_group("Sprint")
## Movement speed multiplier while running.
@export var sprint_speed_scale := 1.5
@export var max_stamina := 100.0
## Stamina used per second while running. A full bar lasts about max_stamina / stamina_drain seconds of running.
@export var stamina_drain := 35.0
## Stamina recovered per second after you stop running.
@export var stamina_regen := 25.0
## Delay after you stop running before stamina starts to recover.
@export var stamina_regen_delay := 0.5
## After stamina runs out, it has to recover to this share before you can run again.
## Otherwise, holding the run button, stamina would be used up the moment a little came back around 0, and the character would stutter between fast and slow.
@export_range(0.0, 1.0) var stamina_recover_ratio := 0.25

@export_group("Weapons")
## Weapons carried, in switching order (default [rifle, grenade]). Shift / pad X switches to the next one, J / RT fires the current one,
## all following the 8-way aim. Changing weapons = changing the resource files here (weapons/*.tres).
@export var weapons: Array[Weapon] = []
## The ultimate (K / pad Y, instant, limited charges). Not in the switching order. Default weapons/ultimate.tres.
@export var ultimate_weapon: Weapon

## Aim direction (Contra style). W + left/right = diagonally up while walking, W alone = straight up on the spot;
## S + left/right = diagonally down while walking; S alone: diagonally down ahead on the ground, straight down in the air; W and S together cancel out; always level while prone.
enum Aim { FORWARD, UP, DIAGONAL_UP, DIAGONAL_DOWN, DOWN }

## Diagonal and straight-down muzzle positions, relative to the body centre (facing right; x flipped when facing left). By convention computed in code, not hung under Visual, independent of the look.
## The diagonal-down muzzle must not be too low: rotated 45° a bullet is about 3px high, so standing on the ground (feet at +8) the muzzle must be above +5, or the bullet sinks into the floor as it leaves.
## Muzzle position per direction, relative to the body centre (facing right; x flipped when facing left). All computed in code, none hung under Visual —
## hit points must not follow the look, or a new skin, or even the recoil offset when firing, would change where bullets come from.
const LEVEL_MUZZLE := Vector2(23, -7)
const UP_MUZZLE := Vector2(8, -27)
const DIAGONAL_UP_MUZZLE := Vector2(22, -21)
const DIAGONAL_DOWN_MUZZLE := Vector2(19, 7)
const DOWN_MUZZLE := Vector2(9, 13)

## Collision height standing / crouching. The feet stay put; only the top of the head comes down.
## Blinks per second while down: slow just after going down, urgent near the end.
const DOWN_BLINK_SLOW := 1.5
const DOWN_BLINK_FAST := 7.0
## How transparent it gets at the darkest point of the blink.
const DOWN_BLINK_DIM := 0.25

const STAND_HEIGHT := 32.0
## Collision height when prone. Enemies' standing shots fly 21~25px above the floor (the gun is raised to the chest), so prone must be lower than 21px to dodge them;
## 12 is chosen to be about as tall as the prone sprite (12~14px), see "align everyone to the art" in CLAUDE.md.
const CROUCH_HEIGHT := 12.0
const HURTBOX_STAND_HEIGHT := 36.0
## How many pixels the appearance kicks back opposite to the shot when firing (recoil, pure presentation, the body and hit checks do not move).
const RECOIL_DISTANCE := 4.0
## Pixels of recoil recovered per second.
const RECOIL_RECOVER := 80.0
## How long (seconds) the platform is ignored when dropping through a one-way platform. Long enough to fall one body height; too long and you pass through the next platform too.
const DROP_THROUGH_TIME := 0.25
## Give a little downward speed at the moment of dropping, to leave the floor at once.
const DROP_THROUGH_SPEED := 80.0

var facing := 1
## Muzzle position and direction of the latest shot (read by effects such as the muzzle flash, see fx.gd).
var last_muzzle_position := Vector2.ZERO
var last_shot_direction := Vector2.RIGHT
var health := 0
var is_crouching := false
var is_sprinting := false
var aim := Aim.FORWARD
var stamina := 0.0

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
## Main weapon slot: holds the cooldown and ammo.
## Which weapon is in hand.
var current_weapon := 0
## One slot per weapon, each with its own cooldown and ammo: switch away and back and both are still there.
var _slots: Array[WeaponSlot] = []
var _ultimate := WeaponSlot.new()
var _recoil := Vector2.ZERO
## The one-way platform being passed through (its collision is ignored while dropping through).
var _dropping_platform: Platform
var _drop_timer := 0.0
var _invincible_timer := 0.0
## Invincibility without blinking (used by the ultimate). The player's timers stop during pause, so it covers the whole freeze.
var _shield_timer := 0.0
var _dead := false
## Where the player last **stood firmly**: falling into a pit brings them back here. Only recorded with feet on solid ground and not being knocked back,
## so it is never recorded in mid-air or at the instant of falling into a pit.
var _safe_spot := Vector2.ZERO
## In vertical stages, the landing spot has to be at least this far from the edge of the view to count as "on screen" (the whole player visible, and the ground under them).
const EDGE_ROOM := 24.0
## How far the down-blink has got (whole part = number of blinks so far).
var _down_blink := 0.0
## Near death (co-op only): out of health you first go down; the partner can pull you up by walking over, and only if nobody comes before the countdown ends do you really die.
var _downed := false
var _down_timer := 0.0
## Statuses on the player (poison, paralysis...). Damage over time goes through take_status_damage, with no invincibility and no knockback.
var statuses := StatusEffects.new()
## The ladder being held (null = not on a ladder). See `_climb()`.
var _ladder: Ladder = null
## Defence stat (reduces damage taken).
var _defense := 0.0
## The speed stat makes sprinting use stamina more slowly (1 = unchanged).
var _stamina_drain_scale := 1.0
var _exhausted := false
var _stamina_regen_timer := 0.0

## Which player this is (0 = player 1, 1 = player 2): decides which set of inputs to read (see act()), which progress to use and which HUD.
@export var player_index := 0

## This player's own progress (`Progress.of(player_index)`, one each in co-op). Taken in `_ready`.
var progress: PlayerProgress

## Appearance layer. Gameplay only calls its interface (facing / pose / aim / hit / blink / death / recoil) and never touches the blocks or colours.
## Which appearance of the skin pack to use (see Skins.build_appearance). **On spawn it is overridden by the `look` in this player's progress** —
## the look belongs to the character, not to the seat; player 2 can pick Biker too.
@export var skin_key := &"biker"
@onready var _visual: Appearance = $Visual
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var _head_check: ShapeCast2D = $HeadCheck


## This player's input action name: for player 1 the action itself (`shoot`), for player 2 with a prefix (`p2_shoot`). All input reading goes through this.
func act(action: StringName) -> StringName:
	return action if player_index == 0 else StringName("p%d_%s" % [player_index + 1, action])


## Still alive? (Enemy targeting, camera following and the co-op restart check all look at this.)
## **Being down counts as not alive**: enemies therefore stop shooting at them, without changing any enemy's code.
func is_alive() -> bool:
	return not _dead and not _downed


## Lying on the ground waiting to be helped up (co-op only).
func is_downed() -> bool:
	return _downed


## Is anyone left in this run: as long as someone is standing, or someone is down waiting to be helped, the stage is not over (co-op).
## Both the level and the HUD need to ask this, so it lives here instead of being written twice.
static func anyone_left(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and (player.is_alive() or player.is_downed()):
			return true
	return false


## How long it can still hold out (seconds). When the countdown ends it is truly dead.
func down_time_left() -> float:
	return _down_timer


func _ready() -> void:
	# Take its own progress first: what it looks like is recorded there too (`look`), and the appearance is installed from it
	progress = Progress.of(player_index)
	skin_key = progress.look
	_visual = Skins.build_appearance(self, skin_key)
	# The two weapon slots use the two weapons equipped in the progress (gun, grenade); without them, the ones set in the scene
	var gun := progress.gear(Equipment.Slot.GUN) as Weapon
	var grenade := progress.gear(Equipment.Slot.GRENADE) as Weapon
	if gun != null and grenade != null:
		weapons = [gun, grenade]
	for weapon in weapons:
		_slots.append(WeaponSlot.new(weapon))
	if not _slots.is_empty():
		_visual.hold(current_slot().weapon.look)
	_ultimate.ammo_changed.connect(func(ammo: int, max_ammo: int) -> void: ultimate_ammo_changed.emit(ammo, max_ammo))
	if ultimate_weapon != null:
		_ultimate.equip(ultimate_weapon)
	_apply_stats()
	health = max_health
	# If it falls before taking a single step, bring it back to the spawn point (unset, it would be brought back to the world origin)
	_safe_spot = global_position
	health_changed.emit(health, max_health)
	progress.stats_changed.connect(_apply_stats)
	statuses.on_damage = take_status_damage
	statuses.changed.connect(_on_status_changed)
	stamina = max_stamina
	stamina_changed.emit(stamina, max_stamina)
	# HeadCheck covers exactly "the extra space needed to stand up": from the standing head height to the prone head height.
	# Worked out from constants rather than fixed in the scene, so changing the crouch height cannot get out of sync.
	var headroom := STAND_HEIGHT - CROUCH_HEIGHT
	(_head_check.shape as RectangleShape2D).size.y = headroom
	_head_check.position.y = -STAND_HEIGHT / 2.0 + headroom / 2.0


func _physics_process(delta: float) -> void:
	if _dead or _downed:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		move_and_slide()
		if _downed:
			_update_downed(delta)
		return

	statuses.tick(delta)
	if _ladder == null:
		_try_grab_ladder()
	if _ladder != null:
		# On a ladder: only climb — no gravity, no walking sideways, **no shooting**, no weapon switching, no going prone. The ultimate still works (it works in any state)
		_climb(delta)
		_handle_ultimate()
		_update_invincibility(delta)
		_shield_timer -= delta
		_check_contact_damage()
		_visual.motion(Appearance.Motion.CLIMB if absf(velocity.y) > 1.0 else Appearance.Motion.HANG)
		return
	_apply_gravity(delta)
	_update_drop_through(delta)
	_update_crouch()
	_handle_jump(delta)
	_handle_horizontal(delta)
	move_and_slide()
	_handle_ultimate()
	_handle_switch()
	_handle_shoot(delta)
	_update_recoil(delta)
	_update_invincibility(delta)
	_shield_timer -= delta
	_check_contact_damage()
	_remember_safe_ground()
	_visual.motion(_motion_state())


## Grab a ladder by pressing "up" in front of it, or "down" while standing on top of it.
## It has to line up horizontally: the body's centre line within half a ladder width of the ladder's centre line.
func _try_grab_ladder() -> void:
	var up := Input.is_action_pressed(act(&"aim_up"))
	var down := Input.is_action_pressed(act(&"aim_down"))
	if not up and not down:
		return
	if is_crouching or not statuses.can_act():
		return
	var feet := global_position.y + STAND_HEIGHT / 2.0
	for node in get_tree().get_nodes_in_group(Ladder.GROUP):
		var ladder := node as Ladder
		if absf(global_position.x - ladder.global_position.x) > ladder.width / 2.0:
			continue
		# Up: the player has to be in front of the ladder (feet below the ladder top, head above the ladder foot)
		if up and feet > ladder.top_y() + 2.0 and global_position.y - STAND_HEIGHT / 2.0 < ladder.bottom_y():
			_grab(ladder)
			return
		# Down: standing on top of the ladder
		if down and is_on_floor() and absf(feet - ladder.top_y()) <= 2.0:
			_grab(ladder)
			global_position.y += 4.0
			return


func _grab(ladder: Ladder) -> void:
	_ladder = ladder
	velocity = Vector2.ZERO
	global_position.x = ladder.global_position.x
	_jump_buffer_timer = 0.0
	if ladder.cap_body() != null:
		add_collision_exception_with(ladder.cap_body())


## Let go of the ladder (reaching the end, jumping off, getting hit and going down all come through here).
func _release_ladder() -> void:
	if _ladder != null and is_instance_valid(_ladder) and _ladder.cap_body() != null:
		remove_collision_exception_with(_ladder.cap_body())
	_ladder = null


func is_climbing() -> bool:
	return _ladder != null


## One frame on a ladder: climb up and down; jump to drop off; step off at the top, let go on landing at the bottom.
func _climb(_delta: float) -> void:
	var dir := signf(Input.get_axis(act(&"aim_up"), act(&"aim_down")))
	if Input.is_action_just_pressed(act(&"jump")):
		# With a left/right direction it jumps off that way, without one it simply lets go and drops
		var side := signf(Input.get_axis(act(&"move_left"), act(&"move_right")))
		_release_ladder()
		if side != 0.0:
			facing = signi(side)
			_visual.face(facing)
			velocity = Vector2(side * move_speed, jump_velocity * ladder_jump_scale)
		else:
			velocity = Vector2.ZERO
		return
	velocity = Vector2(0.0, dir * climb_speed)
	move_and_slide()
	var feet := global_position.y + STAND_HEIGHT / 2.0
	if feet <= _ladder.top_y():
		# Reached the top: step onto the floor at the top of the ladder (the cover's collision comes back and holds them)
		global_position.y = _ladder.top_y() - STAND_HEIGHT / 2.0
		velocity = Vector2.ZERO
		_release_ladder()
	elif dir > 0.0 and (is_on_floor() or feet >= _ladder.bottom_y() + 2.0):
		_release_ladder()


## Remember where the player last stood firmly. **They must really be standing**: on the ground, not flying horizontally or vertically,
## before it counts as a spot to bring them back to.
func _remember_safe_ground() -> void:
	if is_on_floor() and absf(velocity.y) < 1.0:
		_safe_spot = global_position


## What it is doing this frame, for the appearance to pick a clip. Prone is not stated here, it goes through `pose()` (see Appearance.Motion).
func _motion_state() -> Appearance.Motion:
	if not is_on_floor():
		return Appearance.Motion.FALL if velocity.y > 0.0 else Appearance.Motion.JUMP
	if absf(velocity.x) < 1.0:
		return Appearance.Motion.IDLE
	return Appearance.Motion.RUN if is_sprinting else Appearance.Motion.WALK


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _handle_jump(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta

	if Input.is_action_just_pressed(act(&"jump")):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	# Contra-style drop through a platform: standing on a one-way platform, holding "down" and pressing jump drops straight through instead of jumping.
	if _jump_buffer_timer > 0.0 and is_on_floor() and Input.is_action_pressed(act(&"aim_down")):
		var platform := _one_way_floor()
		if platform != null:
			_drop_through(platform)
			return

	var can_jump := _jump_buffer_timer > 0.0 and _coyote_timer > 0.0
	if can_jump and is_crouching:
		# You can jump while crouching too, but only if you can stand up: with something overhead you cannot jump.
		if _head_blocked():
			can_jump = false
		else:
			_set_crouching(false)

	if can_jump:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		GameEvents.report(&"jump", self)

	if Input.is_action_just_released(act(&"jump")) and velocity.y < 0.0:
		velocity.y *= jump_cut


## The one-way platform underfoot; null when standing on solid ground (or on nothing).
## Judged from the collisions of the last move_and_slide, so you can only drop through when really standing on the platform.
func _one_way_floor() -> Platform:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y > -0.7:
			continue # Not the surface underfoot
		var platform := collision.get_collider() as Platform
		if platform != null and platform.one_way:
			return platform
	return null


## Start passing through this platform: exclude it from collisions for now and push down a little.
func _drop_through(platform: Platform) -> void:
	_dropping_platform = platform
	_drop_timer = DROP_THROUGH_TIME
	add_collision_exception_with(platform)
	velocity.y = maxf(velocity.y, DROP_THROUGH_SPEED)
	# Clear the jump buffer, or it would jump again right after dropping through.
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


## When the time is up restore collision with that platform (by then the player is below it and will not be pushed back up).
func _update_drop_through(delta: float) -> void:
	if _drop_timer <= 0.0:
		return
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	if _dropping_platform != null and is_instance_valid(_dropping_platform):
		remove_collision_exception_with(_dropping_platform)
	_dropping_platform = null


func _handle_horizontal(delta: float) -> void:
	# Once the stick passes the dead zone (0.3) it walks at full speed instead of scaling with how far it is pushed — the habit of pixel side-scrollers; a keyboard only gives 0 or 1 anyway.
	var direction := signf(Input.get_axis(act(&"move_left"), act(&"move_right")))
	# Statuses such as paralysis: cannot move
	if not statuses.can_act():
		direction = 0.0
	_update_sprint(delta, direction)
	var control := 1.0 if is_on_floor() else air_control
	var speed := move_speed * _speed_scale()
	if direction != 0.0:
		facing = signi(direction)
		_visual.face(facing)
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * control * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * control * delta)


func _speed_scale() -> float:
	var status := statuses.move_scale()
	if is_crouching:
		return crouch_speed_scale * status
	if is_sprinting:
		return sprint_speed_scale * status
	return status


## Holding the run button while moving speeds up and uses stamina; when not running, stamina starts recovering after a short delay.
## Holding the run button while standing still is not running and uses no stamina; you cannot run while prone.
func _update_sprint(delta: float, direction: float) -> void:
	var wants := Input.is_action_pressed(act(&"sprint")) and direction != 0.0 and not is_crouching
	is_sprinting = wants and not _exhausted and stamina > 0.0

	# Update _exhausted before changing stamina: when stamina_changed fires the state is already up to date, and the HUD changes colour from it.
	if is_sprinting:
		var drained := stamina - stamina_drain * _stamina_drain_scale * delta
		if drained <= 0.0:
			_exhausted = true
			GameEvents.report(&"stamina_exhausted", self)
		_set_stamina(drained)
		_stamina_regen_timer = stamina_regen_delay
	elif _stamina_regen_timer > 0.0:
		_stamina_regen_timer -= delta
	else:
		var regained := stamina + stamina_regen * delta
		if _exhausted and regained >= max_stamina * stamina_recover_ratio:
			_exhausted = false
		_set_stamina(regained)


## Stamina ran out and has not yet recovered enough to run again.
func is_exhausted() -> bool:
	return _exhausted


func _set_stamina(value: float) -> void:
	var clamped := clampf(value, 0.0, max_stamina)
	if clamped == stamina:
		return
	stamina = clamped
	stamina_changed.emit(stamina, max_stamina)


func _update_crouch() -> void:
	# You can only crouch on purpose on the ground; releasing crouch in the air stands up automatically.
	var wants := Input.is_action_pressed(act(&"crouch")) and is_on_floor()
	if wants == is_crouching:
		return
	if wants:
		_set_crouching(true)
	elif not _head_blocked():
		_set_crouching(false)


func _set_crouching(value: bool) -> void:
	is_crouching = value
	var height := CROUCH_HEIGHT if value else STAND_HEIGHT
	var lowered := (STAND_HEIGHT - height) / 2.0
	# The collision shape and hurtbox are lowered together and shifted down, keeping the feet in place.
	(_shape.shape as RectangleShape2D).size.y = height
	_shape.position.y = lowered
	(_hurtbox_shape.shape as RectangleShape2D).size.y = HURTBOX_STAND_HEIGHT - (STAND_HEIGHT - height)
	_hurtbox_shape.position.y = lowered
	_visual.pose(height / STAND_HEIGHT, lowered)


## World position of the collision shape's centre. 6px below global_position when prone; enemies aim their sight here.
func body_center() -> Vector2:
	return _shape.global_position


## The hitbox as a rectangle in the world (shorter when prone). Attacks that sweep a line (the basement boss's laser) use it to check for contact.
func hit_box() -> Rect2:
	var size := (_shape.shape as RectangleShape2D).size
	return Rect2(_shape.global_position - size / 2.0, size)


## Is something overhead in the way? If so, you cannot stand up.
func _head_blocked() -> bool:
	_head_check.force_shapecast_update()
	for i in _head_check.get_collision_count():
		var collider := _head_check.get_collider(i)
		# One-way platforms can be passed through from below, so they do not block your head.
		if collider is Platform and (collider as Platform).one_way:
			continue
		return true
	return false


## J fires the current weapon in the current aim direction (aim rules: see Aim). Lying still you can only fire level (the bullet skims the floor); crawling you cannot fire.
func _handle_shoot(delta: float) -> void:
	# Every weapon's cooldown keeps running: the one you switched away from cools down too.
	for slot in _slots:
		slot.tick(delta)
	var moving := Input.get_axis(act(&"move_left"), act(&"move_right")) != 0.0
	_update_aim(moving)
	var pressed := Input.is_action_pressed(act(&"shoot")) if current_slot().weapon.automatic else Input.is_action_just_pressed(act(&"shoot"))
	# No firing at all while prone: neither rifle nor grenade, crawling or not. To shoot, stand up first.
	# (The ultimate does not come through here; it can be used in any state.)
	if is_crouching or not pressed or not current_slot().is_ready() or not statuses.can_act():
		return
	_shoot(aim_vector())


func _update_aim(moving: bool) -> void:
	var up := Input.is_action_pressed(act(&"aim_up"))
	var down := Input.is_action_pressed(act(&"aim_down"))
	if is_crouching or up == down:
		aim = Aim.FORWARD
	elif up:
		aim = Aim.DIAGONAL_UP if moving else Aim.UP
	elif moving or is_on_floor():
		aim = Aim.DIAGONAL_DOWN
	else:
		aim = Aim.DOWN
	# Placeholder art: show the gun for the aim direction.
	_visual.aim(aim_vector())


## Bullet direction for the current aim (unit vector).
func aim_vector() -> Vector2:
	match aim:
		Aim.UP:
			return Vector2.UP
		Aim.DIAGONAL_UP:
			return Vector2(facing, -1).normalized()
		Aim.DIAGONAL_DOWN:
			return Vector2(facing, 1).normalized()
		Aim.DOWN:
			return Vector2.DOWN
	return Vector2(facing, 0)


## K / pad Y fires the ultimate. Usable in any state (prone, crawling, in the air); see Ultimate for the effect.
func _handle_ultimate() -> void:
	if _ultimate.weapon == null or not Input.is_action_just_pressed(act(&"ultimate")) or not _ultimate.is_ready():
		return
	_ultimate.fire(get_parent(), global_position, Vector2(facing, 0), self)


## Ultimate charges left.
func ultimate_ammo() -> int:
	return _ultimate.ammo


## Invincibility without blinking for seconds (keeps a longer one if there already is one).
func grant_invincibility(seconds: float) -> void:
	_shield_timer = maxf(_shield_timer, seconds)


func is_invincible() -> bool:
	return _invincible_timer > 0.0 or _shield_timer > 0.0


func _handle_switch() -> void:
	if Input.is_action_just_pressed(act(&"switch_weapon")):
		switch_weapon()


## Switch to the next weapon (back to the first after the last).
func switch_weapon() -> void:
	if _slots.size() < 2:
		return
	current_weapon = (current_weapon + 1) % _slots.size()
	_visual.hold(current_slot().weapon.look)
	weapon_switched.emit(current_weapon, current_slot().weapon)
	GameEvents.report(&"weapon_switch", self)


func current_slot() -> WeaponSlot:
	return _slots[current_weapon]


## Replace weapon number index with weapon (future weapon upgrade pickups call this): cooldown cleared, ammo refilled.
func equip_weapon(index: int, weapon: Weapon) -> void:
	weapons[index] = weapon
	_slots[index].equip(weapon)
	_apply_stats()
	if index == current_weapon:
		_visual.hold(weapon.look)
		weapon_switched.emit(current_weapon, weapon)


## Fire the current weapon once in direction (ignores the cooldown; _handle_shoot checked it already, and tests call this directly).
## All weapons fire from the same set of muzzles (see _muzzle_position).
func _shoot(direction: Vector2) -> void:
	last_muzzle_position = _muzzle_position(direction)
	last_shot_direction = direction
	_recoil = -direction * RECOIL_DISTANCE
	_visual.kick(_recoil)
	current_slot().fire(get_parent(), last_muzzle_position, direction, self)


## Muzzle position: the body origin (= the centre of the standing collision shape) + the constant offset for the direction, x flipped when facing left.
## You cannot fire while prone, so there is no "prone muzzle" — the player's height rules only look at standing.
func _muzzle_position(direction: Vector2) -> Vector2:
	var offset := LEVEL_MUZZLE
	if direction == Vector2.UP:
		offset = UP_MUZZLE
	elif direction == Vector2.DOWN:
		offset = DOWN_MUZZLE
	elif direction.y != 0.0:
		offset = DIAGONAL_UP_MUZZLE if direction.y < 0.0 else DIAGONAL_DOWN_MUZZLE
	return global_position + Vector2(offset.x * facing, offset.y)


## Recoil: on firing, the appearance kicks back opposite the shot, then springs back.
## Only the position of Visual changes; the body, collision shape, muzzle and bullets are all unaffected.
func _update_recoil(delta: float) -> void:
	if _recoil == Vector2.ZERO:
		return
	_recoil = _recoil.move_toward(Vector2.ZERO, RECOIL_RECOVER * delta)
	_visual.kick(_recoil)


func _update_invincibility(delta: float) -> void:
	if _invincible_timer <= 0.0:
		return
	_invincible_timer -= delta
	if _invincible_timer <= 0.0:
		_visual.blink(1.0)
	else:
		# Toggle visibility every 0.05 seconds for the blinking effect.
		_visual.blink(0.3 if int(_invincible_timer / 0.05) % 2 == 0 else 1.0)


## Checked continuously while standing on / touching an enemy; once invincibility ends you get hurt again.
func _check_contact_damage() -> void:
	if is_invincible():
		return
	for body in _hurtbox.get_overlapping_bodies():
		if body is Enemy:
			var enemy := body as Enemy
			take_damage(enemy.contact_damage, enemy.global_position)
			# Tell it about the bump too: a chasing D bounces back; otherwise it would stay glued on and hit again as soon as the invincibility frames end
			enemy.bounced_off(global_position)
			return


## Read the stats from the progress: life → max health (raising the cap heals by the same amount), attack → damage multiplier,
## speed → cooldown multiplier and sprint stamina multiplier, defence is kept for when you get hit.
## Read once on spawn, then again whenever the stats change (levelling up, spending points, changing gear).
func _apply_stats() -> void:
	var life := int(progress.stat(Balance.LIFE))
	if max_health > 0 and life > max_health and not _dead:
		health += life - max_health
	max_health = life
	health = mini(health, max_health)
	_defense = progress.stat(Balance.DEFENSE)
	var damage := Balance.damage_scale(progress.stat(Balance.ATTACK))
	var cooldown := Balance.cooldown_scale(progress.stat(Balance.SPEED))
	_stamina_drain_scale = cooldown
	for slot in _slots:
		slot.damage_scale = damage
		slot.cooldown_scale = cooldown
	health_changed.emit(health, max_health)


## Apply a status (called when bullets or grenades hit). Resistance comes from the equipped gear (the resistance in this player's progress).
func apply_status(effect: StatusEffect) -> void:
	if _dead or _downed or effect == null:
		return
	statuses.apply(effect, progress.resistance(effect.id))


## A status applied / removed: tell the appearance (tint); the HUD line listens to `status_changed`.
signal status_changed(id: StringName, active: bool)


func _on_status_changed(id: StringName, active: bool) -> void:
	if _visual != null and _visual.has_method(&"show_status"):
		_visual.call(&"show_status", id, active)
	status_changed.emit(id, active)


## Damage over time from a status: ignores defence, triggers no invincibility, no knockback (resistance is the defence against it).
func take_status_damage(amount: int) -> void:
	if _dead or _downed or amount <= 0:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()


## Called by enemy bullets or contact damage. `source_position` decides the knockback direction. Defence reduces the damage through Balance.damage_taken.
## `from` is the attacker; unused on the player's side (enemies use it to credit the reward), but the signature must match the enemies' exactly —
## `Bullet` finds targets through `has_method("take_damage")`, so both sides need the same name and signature.
func take_damage(amount: int, source_position := Vector2.INF, _from: Node = null) -> void:
	# A downed player cannot be hurt: enemies do not aim at them anyway (is_alive is false), but stray bullets and contact damage still run into them,
	# and without this the countdown would keep being refreshed.
	if _dead or _downed or is_invincible():
		return
	health -= Balance.damage_taken(amount, _defense)
	health_changed.emit(health, max_health)
	if health <= 0:
		_go_down()
		return
	GameEvents.report(&"player_hurt", self)
	_invincible_timer = invincible_time
	# One hit knocks you off the ladder
	_release_ladder()
	var away := 1.0 if source_position == Vector2.INF else signf(global_position.x - source_position.x)
	if away == 0.0:
		away = 1.0
	velocity = Vector2(hurt_knockback.x * away, hurt_knockback.y)


## Flung away: just set a velocity; gravity and air control wear it down as usual.
## The hit itself (losing health, invincibility frames) goes through `take_damage`; this only decides how far you fly — basement 4-F uses it.
func shove(push: Vector2) -> void:
	if _dead or _downed:
		return
	_release_ladder()
	velocity = push


## Out of health: in co-op go down and wait for help first, alone die at once.
func _go_down() -> void:
	_release_ladder()
	if Session.player_count < 2:
		_die()
		return
	_downed = true
	health = 0
	_down_timer = down_time
	_down_blink = 0.0
	velocity.x = 0.0
	if is_crouching:
		_set_crouching(false)
	_visual.show_dead()
	downed.emit()
	GameEvents.report(&"player_down", self)


## Every frame while down: the partner walking up pulls you up automatically; otherwise the countdown runs and at the end you really die.
func _update_downed(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var mate := node as Player
		if mate != null and mate != self and mate.is_alive() 				and global_position.distance_to(mate.global_position) <= revive_range:
			revive()
			return
	_down_timer -= delta
	_blink_while_down(delta)
	if _down_timer <= 0.0:
		_die()


## A downed player **blinks faster and faster** — slowly while there is plenty of time left, urgently near the end,
## so the partner can tell at a glance whether there is still time. More direct than a number on the HUD: the eyes are on the characters anyway.
func _blink_while_down(delta: float) -> void:
	var left := clampf(_down_timer / maxf(down_time, 0.001), 0.0, 1.0)
	_down_blink += delta * lerpf(DOWN_BLINK_FAST, DOWN_BLINK_SLOW, left)
	_visual.blink(DOWN_BLINK_DIM if fmod(_down_blink, 1.0) < 0.5 else 1.0)


## Pulled up by the partner: half health back, a short invincibility, carry on fighting.
func revive() -> void:
	if not _downed:
		return
	_downed = false
	_down_timer = 0.0
	_down_blink = 0.0
	_visual.blink(1.0)
	health = maxi(1, int(max_health * revive_health_ratio))
	health_changed.emit(health, max_health)
	_visual.revive()
	grant_invincibility(revive_grace)
	revived.emit()
	GameEvents.report(&"player_revive", self)


## Fell out of the stage (stepped into a pit): **lose a third of max health and get brought back to where you last stood firmly**, plus a short invincibility,
## instead of dying outright. Pits are everywhere in this stage, and replaying the whole stage for one misstep would be too harsh.
## Only bring the player back if there is health left after the loss; if it runs out, go down the usual death path (in co-op, down and waiting for help).
## **Invincibility frames do not protect you**: the second after being hit should not leave you floating in a pit.
func fall_out() -> void:
	if _dead:
		return
	if _downed:
		# A downed player falling in: no health left to lose, so bring them back to keep waiting for the partner
		_respawn_at_safe_ground()
		return
	health -= maxi(1, ceili(max_health * fall_damage_ratio))
	health_changed.emit(health, max_health)
	if health <= 0:
		health = 0
		_go_down()
		return
	GameEvents.report(&"player_hurt", self)
	_respawn_at_safe_ground()


## Bring the player back to where they last stood firmly, standing still, with a short invincibility.
func _respawn_at_safe_ground() -> void:
	_release_ladder()
	global_position = landing_spot()
	velocity = Vector2.ZERO
	grant_invincibility(fall_grace)


## Where to bring the player back to after falling out: **where they last stood firmly**.
## In vertical stages the view only scrolls up, and that spot may already have scrolled off screen (the partner climbed fast and left you behind) —
## bringing you back there would mean falling again at once. So bring you to **where your partner last stood, on screen**; if neither spot is on screen, use the old one anyway.
func landing_spot() -> Vector2:
	var rig := CameraRig.find(get_tree())
	if rig == null or not rig.only_up:
		return _safe_spot
	var view := rig.view_rect().grow(-EDGE_ROOM)
	if view.has_point(_safe_spot):
		return _safe_spot
	for node in get_tree().get_nodes_in_group(&"player"):
		var other := node as Player
		if other != null and other != self and other.is_alive() and view.has_point(other._safe_spot):
			return other._safe_spot
	return _safe_spot


func _die() -> void:
	_release_ladder()
	_dead = true
	_downed = false
	health = 0
	_visual.show_dead()
	died.emit()
	GameEvents.report(&"player_death", self)
