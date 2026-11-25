class_name Enemy
extends CharacterBody2D
## Base class for enemies: health, white hit flash, death, gravity, plus the shared shooting and prone logic. See the subclasses for behaviour.
## Regular enemies (A/B/C/D/E/turret) extend it directly; bosses extend Boss (scripts/boss.gd).

signal died
## Emitted once per bullet fired (once for every bullet of a burst). Muzzle flash and sound from step 3 can hook into this.
signal shot_fired

@export var max_health := 20
## Damage dealt to the player on contact.
@export var contact_damage := 40
## XP and money given to the player when it is destroyed (Progress pays them out on enemy_death).
@export var xp_reward := 10
@export var money_reward := 5
## Status resistances: status id → 0..1 (duration × (1 - resistance), 1 = immune). Mechanical enemies could later be immune to poison and the like.
@export var resist: Dictionary[StringName, float] = {}

## Statuses on this enemy. Enemies only take damage over time for now; slowing and paralysis need changes to each enemy's AI and will be wired up when an enemy can actually be paralysed.
var statuses := StatusEffects.new()
## Who hit it last (the character carried by the bullet, grenade or ultimate). On death the reward goes to that player,
## so in co-op each counts their own. Never hit by anyone (e.g. fell out of the stage) means null, and the reward goes to player 1.
var killed_by: Node
@export var gravity := 1800.0
@export var max_fall_speed := 800.0

@export_group("Shooting")
## Leave empty for an enemy that does not shoot.
@export var bullet_scene: PackedScene
@export var fire_interval := 1.4
@export var detect_range := 300.0
## It fires level shots when the height difference to the player is within this range.
@export var vertical_tolerance := 40.0
## How many shots per round, picked at random in [burst_min, burst_max]. Both 1 means single shots.
## fire_interval counts from the first shot of a round.
@export_range(1, 10) var burst_min := 1
@export_range(1, 10) var burst_max := 1
## Gap between two shots in the same round.
@export var burst_gap := 0.15
## Event reported when firing (the pack looks up a sound by it): patrollers enemy_shoot, turret turret_shoot, E flyer_shoot.
@export var shoot_event := &"enemy_shoot"

@export_group("Diagonal")
## Whether it can stand still and fire diagonally up/down (B, C, turret). When the player is not at the same height but diagonally above/below,
## a patroller stops walking and a turret turns, aims for diagonal_aim_time seconds and fires at 45°; once the player is level again it goes back to normal.
@export var can_aim_diagonally := false
## How long it aims after turning to a diagonal before the first shot (like a Contra turret turning around), giving the player time to react.
@export var diagonal_aim_time := 0.3
@export_group("Prone")
## When the player lies prone within range, the enemy lies down too to hit low. Off by default, i.e. it only fires standing.
@export var can_go_prone := false
## How long after spotting a prone player it lies down too, leaving the player a window to dodge.
@export var prone_reaction_time := 0.4

## Collision height while prone, same as the player. Shots fired standing fly over it.
const PRONE_HEIGHT := 12.0
## It only fires diagonally when the player's direction deviates from level by an angle in this range (bullets always travel at 45°); flatter counts as level, steeper is not fired at.
const DIAGONAL_MIN_ANGLE := 22.5
const DIAGONAL_MAX_ANGLE := 67.5
## Default diagonal muzzle positions, relative to the body centre (facing right; x flipped when facing left). Computed in code, not hung under Visual.
## The diagonal-down y must not be too large: standing on the ground the bullet would sink into the floor the moment it leaves the muzzle.
const DIAGONAL_UP_MUZZLE := Vector2(20, -23)
const DIAGONAL_DOWN_MUZZLE := Vector2(20, -1)

## Aim direction.
enum Aim { LEVEL, DIAGONAL_UP, DIAGONAL_DOWN }

## Every enemy is in this group (the ultimate uses it to find enemies on screen).
const GROUP := &"enemies"

var health := 0
var is_prone := false
var aim := Aim.LEVEL
## Direction and muzzle position of the latest bullet (read by tests and the muzzle flash, see fx.gd).
var last_shot_direction := Vector2.ZERO
var last_muzzle_position := Vector2.ZERO
## Facing, which also decides the bullet direction: -1 left, 1 right.
var facing := -1

var _fire_timer := 0.0
var _burst_left := 0
var _burst_timer := 0.0
## Direction and aim locked at the start of a round: the remaining shots reuse them.
## Otherwise, if the player jumped onto a platform halfway through a level burst, the rest would fire diagonally straight away and skip the diagonal aiming time.
var _burst_direction := Vector2.ZERO
var _burst_aim := Aim.LEVEL
var _prone_timer := 0.0
var _stand_height := 0.0
## How long the current aim direction has been held.
var _aim_timer := 0.0

## Appearance layer. Gameplay only calls its interface and never touches blocks or colours (see appearance.gd).
## Diagonal muzzle positions, set per enemy in its own scene (like the Muzzle marker for level shots):
## with real sprites, set them to where the barrel is in the art, so bullets leave from the muzzle on screen. Defaults are the two constants above.
@export var diagonal_up_muzzle := DIAGONAL_UP_MUZZLE
@export var diagonal_down_muzzle := DIAGONAL_DOWN_MUZZLE

## If the skin pack has an appearance for `skin_key`, `_ready` swaps it in (see Skins.build_appearance).
@export var skin_key := &"walker"
@onready var _visual: Appearance = $Visual
## Muzzle marker, hung on the **body** (not inside `Visual`): it only gives the "how far out" offset;
## the actual muzzle height is computed from the collision shape's centre (see `level_muzzle_position()`), so it does not depend on what the appearance looks like or whether it is squashed.
## Enemies that do not shoot (D) have no muzzle.
@onready var _muzzle: Marker2D = get_node_or_null("Muzzle") as Marker2D
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_visual = Skins.build_appearance(self, skin_key)
	add_to_group(GROUP)
	# This stage's strength multipliers (`Stage`): 23 stages share the same enemies, with health, damage and rewards scaled per stage.
	# With no stage set (the test level, loading a scene directly) every multiplier is 1 and nothing changes.
	max_health = maxi(1, roundi(max_health * Stage.health_scale()))
	contact_damage = maxi(1, roundi(contact_damage * Stage.damage_scale()))
	health = max_health
	statuses.on_damage = take_status_damage
	_apply_visual_facing()
	_stand_height = (_shape.shape as RectangleShape2D).size.y


## Called by bullets (Bullet finds it through has_method("take_damage")).
## `_source_position` is not used yet; it only keeps the same signature as Player.take_damage.
## Apply a status (called when the player's bullets or grenades hit).
func apply_status(effect: StatusEffect) -> void:
	if health <= 0 or effect == null:
		return
	statuses.apply(effect, resist.get(effect.id, 0.0))


## Damage over time from a status: straight off the health, dying as usual (with reward).
func take_status_damage(amount: int) -> void:
	if health <= 0 or amount <= 0:
		return
	health -= amount
	if health <= 0:
		die()


## Status timers run in _process: each enemy writes its own _physics_process, so this way nobody has to remember to call it.
func _process(delta: float) -> void:
	statuses.tick(delta)


func take_damage(amount: int, _source_position := Vector2.INF, from: Node = null) -> void:
	if health <= 0:
		return
	if from != null:
		killed_by = from
	health -= amount
	if health <= 0:
		die()
	else:
		_flash()
		GameEvents.report(&"enemy_hit", self)


## Hit by the ultimate: regular enemies are destroyed outright (regardless of health). Boss overrides this to only take damage.
func hit_by_ultimate(from: Node = null) -> void:
	if from != null:
		killed_by = from
	die()


## Whether the body origin is inside the visible screen (used by the ultimate and boss entrances).
func is_on_screen() -> bool:
	return _visible_rect().has_point(global_position)


## Whether **any part** of the hitbox is on screen (for boss entrances: a wide boss is already half visible and hittable while its centre is still off screen).
func is_partly_on_screen() -> bool:
	var box := (_shape.shape as RectangleShape2D).size
	return _visible_rect().intersects(Rect2(body_center() - box / 2.0, box))


func _visible_rect() -> Rect2:
	var viewport := get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()


func die() -> void:
	died.emit()
	GameEvents.report(&"enemy_death", self)
	# The body is deleted right away; whether the appearance stays to play the death animation is up to the appearance (see Appearance.show_dead)
	_visual.show_dead()
	queue_free()


## Tell the appearance what it is doing this frame (picks the idle / walk / run / air clip). Moving subclasses call this after move_and_slide;
## `fast` means it is charging (D while chasing); the appearance uses a run clip if it has one.
func _report_motion(fast := false) -> void:
	var state := Appearance.Motion.IDLE
	if not is_on_floor():
		state = Appearance.Motion.JUMP if velocity.y < 0.0 else Appearance.Motion.FALL
	elif absf(velocity.x) > 1.0:
		state = Appearance.Motion.RUN if fast else Appearance.Motion.WALK
	_visual.motion(state)


## Living players, nearest first (one when solo, two in co-op).
func players_by_distance() -> Array[Player]:
	var found: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.is_alive():
			found.append(player)
	found.sort_custom(func(a: Player, b: Player) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return found


## The player to shoot at: the **first one it can hit**, nearest first. Not simply the nearest — in co-op the nearest may be hiding behind a wall
## while the one further away stands right in front of it. "Can it hit" is can_target(); each enemy type only changes that one.
func find_target() -> Node2D:
	for player in players_by_distance():
		if can_target(player):
			return player
	return null


## Whether this player can be hit: it can aim at them (aim_for) and can see them.
func can_target(player: Player) -> bool:
	return aim_for(player) >= 0 and has_line_of_sight(player.body_center())


## Whether this distance is within reach: inside detect_range, **or part of this enemy is on screen**.
## When the player can see me (I am on screen), I must be able to see the player — otherwise the player could kill me from the screen before I react.
## So the detection range covers at least the whole screen; facing, height and walls blocking sight still apply.
func within_reach(distance: float) -> bool:
	return distance <= detect_range or is_partly_on_screen()


## Which aim direction to use against this target; -1 if it cannot be hit.
## Level: within reach horizontally (within_reach) and the height difference within vertical_tolerance (the original rule).
## Diagonal (only with can_aim_diagonally): within reach in a straight line, 22.5°~67.5° away from level.
func aim_for(target: Node2D) -> int:
	var offset := target.global_position - global_position
	if within_reach(absf(offset.x)) and absf(offset.y) <= vertical_tolerance:
		return Aim.LEVEL
	if not can_aim_diagonally or not within_reach(offset.length()):
		return -1
	var angle := rad_to_deg(atan2(absf(offset.y), absf(offset.x)))
	if angle < DIAGONAL_MIN_ANGLE or angle > DIAGONAL_MAX_ANGLE:
		return -1
	return Aim.DIAGONAL_UP if offset.y < 0.0 else Aim.DIAGONAL_DOWN


## Subclasses call this every frame with the current target: updates the aim direction and returns the target it may fire at this frame.
## Right after turning to a diagonal it aims for diagonal_aim_time seconds first, returning null meanwhile (no firing).
func update_aim(delta: float, target: Node2D) -> Node2D:
	var wanted: int = Aim.LEVEL if target == null else aim_for(target)
	if wanted < 0:
		wanted = Aim.LEVEL
		target = null
	if wanted != aim:
		aim = wanted as Aim
		_aim_timer = 0.0
		_show_aim()
	else:
		_aim_timer += delta
	if target != null and aim != Aim.LEVEL and _aim_timer < diagonal_aim_time:
		return null
	return target


func is_aiming_diagonally() -> bool:
	return aim != Aim.LEVEL


## A burst is still in progress (it finishes the round even if the player dodged halfway).
func is_firing_burst() -> bool:
	return _burst_left > 0


## It bumped into the player (the player tells it when taking the hit). Does nothing by default —
## standing and patrolling enemies should not move when bumped. D, which chases, overrides it to bounce back a little.
func bounced_off(_from: Vector2) -> void:
	pass


## When the facing or aim direction changes, tell the appearance layer; it decides how to draw it.
func _apply_visual_facing() -> void:
	_visual.face(facing)
	_show_aim()


func _show_aim() -> void:
	_visual.aim(shoot_direction())


## Whether something solid (wall, ground, crawl passage) blocks the line from the muzzle to `point`; one-way platforms do not. See Sight for the rule.
func has_line_of_sight(point: Vector2) -> bool:
	return Sight.is_clear(get_world_2d().direct_space_state, _sight_origin(), point)


## Where sight comes from: the muzzle (you can only hit what you can see). Enemies without a muzzle (D) look from the body centre.
func _sight_origin() -> Vector2:
	return level_muzzle_position()


## When the cooldown is over, fire a round (single or burst) in the current aim direction. Passing null for `target` means no new round should start this frame.
## Once a burst starts it finishes in the direction it started with, even if the player leaves range or moves meanwhile.
func try_shoot(delta: float, target: Node2D) -> void:
	_fire_timer -= delta
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_timer = burst_gap
		return
	if target == null or bullet_scene == null or _fire_timer > 0.0:
		return
	_fire_timer = fire_interval
	_burst_direction = shoot_direction()
	_burst_aim = aim
	_fire_one()
	_burst_left = randi_range(burst_min, maxi(burst_min, burst_max)) - 1
	_burst_timer = burst_gap


## Bullets hang under the enemy's parent, so they keep flying after the enemy dies.
func _fire_one() -> void:
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.direction = burst_direction()
	# Bullet damage scales with the stage too (the bullet scene holds stage 1 values)
	if not is_equal_approx(Stage.damage_scale(), 1.0) and bullet.has_method("scale_damage"):
		bullet.scale_damage(Stage.damage_scale())
	last_shot_direction = bullet.direction
	last_muzzle_position = _muzzle_position()
	get_parent().add_child(bullet)
	bullet.global_position = last_muzzle_position
	_visual.fire()
	shot_fired.emit()
	GameEvents.report(shoot_event, self)


## Which way bullets fly: by the aim direction, level or 45° diagonally up/down; flying enemies override this to point down.
## Launch a projectile that **works out its own trajectory** (grenade style, not going through `bullet_scene`).
## It hangs under this enemy's parent, so it finishes its flight and explodes even if this enemy dies; by convention `launch()` is called before it joins the scene tree.
func launch_projectile(scene: PackedScene, offset: Vector2, direction: Vector2) -> Node2D:
	var thrown := scene.instantiate() as Node2D
	thrown.call(&"launch", direction)
	get_parent().add_child(thrown)
	thrown.global_position = global_position + Vector2(offset.x * facing, offset.y)
	return thrown


## Which way **this shot** of the round flies. By default the direction locked at the start of the round —
## if the player jumps onto a platform halfway through a level burst, the remaining shots should not swing diagonal.
## Subclasses that want a round to fan out override this (the industrial zone boss does at low health).
func burst_direction() -> Vector2:
	return _burst_direction


func shoot_direction() -> Vector2:
	match aim:
		Aim.DIAGONAL_UP:
			return Vector2(facing, -1).normalized()
		Aim.DIAGONAL_DOWN:
			return Vector2(facing, 1).normalized()
	return Vector2(facing, 0)


## Muzzle position (for the aim locked this round): level shots use the muzzle, diagonals are computed from the body centre.
func _muzzle_position() -> Vector2:
	if _burst_aim == Aim.LEVEL:
		return level_muzzle_position()
	var offset := diagonal_up_muzzle if _burst_aim == Aim.DIAGONAL_UP else diagonal_down_muzzle
	return global_position + Vector2(offset.x * signf(_burst_direction.x), offset.y)


## World position of the collision shape's centre. When prone the shape is lowered and its centre follows, so all hit points are based on it.
func body_center() -> Vector2:
	return _shape.global_position


## Muzzle position for level shots (E's straight-down shot goes through here too): **collision shape centre** + the Muzzle marker's offset, x flipped when facing left.
## Working from the collision shape instead of reading the marker's world position makes the rule "prone shots skim the floor"
## depend on the shape's height rather than on the placeholder being squashed — so switching to sprites cannot change the rule.
func level_muzzle_position() -> Vector2:
	if _muzzle == null:
		return body_center()
	# Standing, the gun is raised to the chest (the marker's y is negative); **prone it is not raised**, and the gun drops back to the shape centre near the floor.
	# Without this split, a prone shape is only 12px tall with its centre 6px above the floor, and subtracting the chest offset would put the muzzle below the ground.
	var lift := 0.0 if is_prone else _muzzle.position.y
	return body_center() + Vector2(_muzzle.position.x * facing, lift)


## Subclasses call this every frame with the current target: if the target is prone it lies down after prone_reaction_time, otherwise it stands up at once.
func update_prone(delta: float, target: Node2D) -> void:
	var player := target as Player
	if not (can_go_prone and player != null and player.is_crouching):
		_prone_timer = 0.0
		if is_prone:
			set_prone(false)
		return
	if is_prone:
		return
	_prone_timer += delta
	if _prone_timer >= prone_reaction_time:
		set_prone(true)


## Same approach as the player crouching: the shape is lowered and shifted down so the feet stay put, and the appearance is squashed.
## The muzzle is computed from the shape centre (level_muzzle_position), so it follows the floor by itself, regardless of how the appearance is squashed.
func set_prone(value: bool) -> void:
	if value and not is_prone:
		GameEvents.report(&"enemy_prone", self)
	is_prone = value
	var height := PRONE_HEIGHT if value else _stand_height
	var lowered := (_stand_height - height) / 2.0
	(_shape.shape as RectangleShape2D).size.y = height
	_shape.position.y = lowered
	_visual.pose(height / _stand_height, lowered)


func _flash() -> void:
	_visual.flash_hit()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
