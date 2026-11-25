class_name BossSkull
extends Boss
## Stage 4 (basement) boss, the "skull": floats in the top screen of the shaft and **sweeps a laser in from the side**.
##
## This stage climbs upward and the boss area is the top screen of the shaft with a few layers of platforms. All its attacks force the player to **change layers**:
## 1. **Laser** (main attack): floats up and down on its side to line up with the player's layer; **stops to charge** (the first two attack frames —
## that pause is the warning the player gets to see), then a beam sweeps across the whole shaft up to the opposite wall
## (one-way platforms do not block it, same as bullets). Dodge by **changing layers** — jump up, drop down, or lie prone during the charge:
## the laser aims at a standing player's body centre and is 6px thick, so a prone player fits under it.
## 2. **Summon**: little skulls drop from its hand (`SkullMinion`), drift toward the player, hurt on contact and die in two shots.
## At most `minion_cap` at a time, or they would fill the screen.
## 3. **Switch sides**: every two attacks it flies from one side of the shaft to the other, so the laser sometimes comes from the left, sometimes from the right.
## 4. **Bone shots**: when the player gets **right below / right above** it (the laser shoots from the bony hand toward the middle of the shaft and cannot reach beside it),
## or stands at a height the laser cannot reach, it fires a fan of bullets at the player (the base class burst, each shot offset a little).
## **2026-10 playtest feedback**: it used to have only the laser, so standing underneath was a safe spot and the boss was too easy.
##
## The rotation is fixed (laser, laser, summon...), for the same reason as the wheel mech: two rounds and you know the rhythm, and when you die you know why.
## **Phase 2 below half health**: it sneers first (`sneer`) and reports `boss_enrage` (the same event and rule as the previous two bosses:
## at or below half health, checked on every hit, reported once), then the charge gets shorter and the laser **fires twice in a row** — first at the player's layer,
## right after that at the neighbouring layer, so one dodge is not enough.
## When it dies, any little skulls left shatter with it (no reward — the player did not shoot them down).

@export_group("Movement")
## How far horizontally the other side is from the spawn point (negative if it spawns on the right). The shaft is 576 wide with 72 left on each side.
@export var lane_offset := -448.0
## How high above its spawn point it may float at most (the spawn point is its lowest position). **Enough to reach every layer of the boss area**:
## the body centres of players on the three layers are at 304 / 244 / 184, so 120 up from 288 lines up with the top layer.
## Not higher: with the player on the floor the view is 60..420 (the camera looks 64 further up), so floating too high takes it off screen, sniping from out of view.
@export var rise := 140.0
## Speed of lining up vertically and of flying over when switching sides.
@export var climb_speed := 140.0
@export var cross_speed := 260.0
## Longest it waits to line up (the player keeps jumping; even if it cannot catch up it has to start firing).
@export var align_time := 1.2

@export_group("Beam")
@export var charge_time := 0.7
@export var beam_time := 0.45
@export var beam_damage := 60
## Half the thickness of the laser (hit check). Matches the 6px thick beam in the art.
@export var beam_half := 3.0
## Longest the laser can reach (it stops at walls; this is only the cap).
@export var beam_range := 640.0
## Rest between two attacks.
@export var rest_time := 0.8

@export_group("Volley")
## When the player is this close horizontally (right below / right above it) it fires bone shots instead — the laser cannot reach beside it.
@export var under_reach := 120.0
## Degrees between shots in the fan. Shots per round and the gap between them come from the base class `burst_min/max` and `burst_gap` (set in the scene).
@export var volley_spread := 15.0

@export_group("Summon")
@export var minion_scene: PackedScene
## It summons every this many attacks (which attack is the summon).
@export var summon_every := 3
@export var summon_count := 2
@export var minion_cap := 3

@export_group("Enraged")
@export_range(0.0, 1.0) var enrage_below := 0.5
## Phase 2 charge time is multiplied by this (shorter).
@export var enrage_rush := 0.6
## The second laser hits the neighbouring layer: how far up or down that is (one layer's height).
@export var second_beam_step := 60.0
@export var sneer_time := 0.5

## Where the laser leaves the bony hand (relative to the body centre, facing right; x flipped when facing left). Measured on the art: hand at (52, 64~67), body centre at (32, 50).
const BEAM_ORIGIN := Vector2(20, 16)
## On which frame the little skulls drop out when summoning (frame 5 of Attack3; one-shot clips run at 12 frames / second).
const SUMMON_DROP := 4.0 / EnemySpriteAppearance.ONCE_FPS
const SUMMON_TIME := 6.0 / EnemySpriteAppearance.ONCE_FPS

enum Move {ALIGN, CHARGE, BEAM, REST, SUMMON, SWAP, SNEER, VOLLEY}

var _move := Move.REST
var _left := 0.0
var _home := Vector2.ZERO
var _lanes: Array[float] = []
var _lane := 0
## The height the laser is locked to (world y), and how many beams this round has fired.
var _beam_y := 0.0
var _beams_this_round := 0
var _attacks := 0
var _summoned := false
var _enraged := false
var _minions: Array[Enemy] = []
## Whether the bone-shot round has started and which shot of it we are on (to spread the fan).
var _volley_started := false
var _fan_index := 0


func _ready() -> void:
	super()
	_home = global_position
	_lanes = [_home.x, _home.x + lane_offset]
	_left = rest_time


func _boss_process(delta: float) -> void:
	_forget_dead_minions()
	var target := find_target()
	_face_the_shaft()
	match _move:
		Move.ALIGN:
			_left -= delta
			var goal := _goal_height(target)
			velocity = Vector2(0.0, clampf((goal - global_position.y) / delta, -climb_speed, climb_speed))
			if target != null and wants_volley(target) and _beams_this_round == 0:
				# The player slipped under it while it was lining up: the laser cannot reach, fire bone shots instead
				velocity = Vector2.ZERO
				_start_volley()
			elif target != null and absf(goal - global_position.y) < 1.0:
				# **Once lined up, snap straight to that height**: the fraction of a pixel left over comes from bobbing while resting,
				# and without removing it the locked laser height would differ every time
				global_position.y = goal
				_start_charge()
			elif target != null and _left <= 0.0:
				_start_charge()
		Move.CHARGE:
			velocity = Vector2.ZERO
			_left -= delta
			if _left <= 0.0:
				_move = Move.BEAM
				_left = beam_time
		Move.BEAM:
			velocity = Vector2.ZERO
			_burn()
			_left -= delta
			if _left <= 0.0:
				_beams_this_round += 1
				if _enraged and _beams_this_round < 2:
					_beam_y = _second_beam_height(target)
					_move = Move.ALIGN
					_left = align_time
				else:
					_finish_attack()
		Move.REST:
			velocity = _hover(delta)
			_left -= delta
			if _left <= 0.0 and target != null:
				_next_attack()
		Move.SUMMON:
			velocity = Vector2.ZERO
			_left -= delta
			if not _summoned and SUMMON_TIME - _left >= SUMMON_DROP:
				_summon()
			if _left <= 0.0:
				_finish_attack()
		Move.SWAP:
			var to := Vector2(_lanes[_lane], global_position.y)
			var step := to - global_position
			velocity = step.limit_length(cross_speed * delta) / delta
			if step.length() < 1.0:
				_move = Move.ALIGN
				_left = align_time
		Move.VOLLEY:
			velocity = Vector2.ZERO
			try_shoot(delta, target if not _volley_started else null)
			if not _volley_started and is_firing_burst():
				_volley_started = true
			elif _volley_started and not is_firing_burst():
				_finish_attack()
		Move.SNEER:
			velocity = Vector2.ZERO
			_left -= delta
			if _left <= 0.0:
				_move = Move.REST
				_left = rest_time * 0.5
	move_and_slide()
	# Turn to face again after moving: on the frame it arrives after switching sides, the earlier facing still pointed at the destination
	_face_the_shaft()
	_report_motion(_move == Move.SWAP)
	_show_beam()


## How high to float this time: the laser exit (16 below the body centre) lines up with the player's body centre.
## When the second laser already has its height locked (`_beam_y`), float to that.
func _goal_height(target: Node2D) -> float:
	var want := global_position.y
	if _enraged and _beams_this_round == 1:
		want = _beam_y - BEAM_ORIGIN.y
	elif target != null:
		want = (target as Player).body_center().y - BEAM_ORIGIN.y
	return clampf(want, _home.y - rise, _home.y)


func _start_charge() -> void:
	_beam_y = global_position.y + BEAM_ORIGIN.y
	_move = Move.CHARGE
	_left = charge_time * (enrage_rush if _enraged else 1.0)
	# The second laser charges for less time: it follows straight after the first
	if _enraged and _beams_this_round == 1:
		_left *= 0.5


## The second beam hits the neighbouring layer: if the player already changed layers, follow them; if not, hit the layer above them (or below, if there is nothing above).
func _second_beam_height(target: Node2D) -> float:
	var first := _beam_y
	if target != null:
		var now := (target as Player).body_center().y
		if absf(now - first) > beam_half * 4.0:
			return now
	var up := first - second_beam_step
	var lowest_origin := _home.y - rise + BEAM_ORIGIN.y
	return up if up >= lowest_origin else first + second_beam_step


func _next_attack() -> void:
	_attacks += 1
	_beams_this_round = 0
	var target := find_target()
	if _attacks % summon_every == 0 and _minions.size() < minion_cap:
		_move = Move.SUMMON
		_left = SUMMON_TIME
		_summoned = false
		if _visual.has_method(&"play"):
			_visual.call(&"play", &"summon")
	elif target != null and wants_volley(target):
		_start_volley()
	elif _attacks % 2 == 0:
		_lane = 1 - _lane
		_move = Move.SWAP
	else:
		_move = Move.ALIGN
		_left = align_time


## Can the laser not reach this player: beside it (right below / right above — the laser shoots toward the middle of the shaft),
## or outside the heights it can float to (the laser only fires level).
func wants_volley(target: Node2D) -> bool:
	var player := target as Player
	var at := player.body_center() if player != null else target.global_position
	if absf(at.x - global_position.x) < under_reach:
		return true
	var lowest := _home.y + BEAM_ORIGIN.y
	var highest := _home.y - rise + BEAM_ORIGIN.y
	return at.y > lowest + 24.0 or at.y < highest - 24.0


func _start_volley() -> void:
	_move = Move.VOLLEY
	_volley_started = false
	_fire_timer = 0.0


func is_volleying() -> bool:
	return _move == Move.VOLLEY


## Direction of this round of bone shots: from the bony hand at the player's body centre (up or down both work). The base class calls this once at the start of a round; the fan counter is reset here too.
func shoot_direction() -> Vector2:
	_fan_index = 0
	var target := find_target()
	if target == null:
		return Vector2(facing, 0.0)
	return ((target as Player).body_center() - _muzzle_position()).normalized()


## This shot: spread left and right around the locked direction (the middle shot points straight at the player).
func burst_direction() -> Vector2:
	var count := maxi(1, burst_max)
	var step := (_fan_index % count) - (count - 1) / 2.0
	_fan_index += 1
	return super().rotated(deg_to_rad(step * volley_spread))


## Bone shots leave from the bony hand (the same opening as the laser).
func _muzzle_position() -> Vector2:
	return global_position + Vector2(BEAM_ORIGIN.x * facing, BEAM_ORIGIN.y)


func _finish_attack() -> void:
	_move = Move.REST
	_left = rest_time


## Remove dead little skulls from the list.
## **Do not use `filter(func(m: Enemy) ...)`**: the player's bullets are processed after the boss, so a skull killed this frame is freed at the end of the frame,
## and next frame this sees an already freed object — passing it to a typed parameter is an error, `filter` then returns an untyped array,
## and assigning that back to `Array[Enemy]` errors again, every frame (in the 2026-10 playtest the editor stopped here and it looked like a crash).
## The loop variable is untyped too; ask `is_instance_valid` before using it.
func _forget_dead_minions() -> void:
	var alive: Array[Enemy] = []
	for minion in _minions:
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			alive.append(minion)
	_minions = alive


## Little skulls drop out from under the bony hand, never more than the cap.
func _summon() -> void:
	_summoned = true
	if minion_scene == null:
		return
	for i in summon_count:
		if _minions.size() >= minion_cap:
			break
		var minion := minion_scene.instantiate() as Enemy
		get_parent().add_child(minion)
		minion.global_position = global_position + Vector2(BEAM_ORIGIN.x * facing, BEAM_ORIGIN.y + 8.0 * i)
		_minions.append(minion)


## While the beam is on: anyone whose body touches the band takes a hit (invincibility frames stop a second hit from the same beam).
func _burn() -> void:
	var from := beam_start()
	var to := beam_end()
	var left := minf(from.x, to.x)
	var right := maxf(from.x, to.x)
	for player in players_by_distance():
		var box := player.hit_box()
		if box.end.x < left or box.position.x > right:
			continue
		if box.position.y > _beam_y + beam_half or box.end.y < _beam_y - beam_half:
			continue
		player.take_damage(roundi(beam_damage * Stage.damage_scale()), from, self)


## Where the laser starts and where it ends (at the first solid object; one-way platforms do not block it).
func beam_start() -> Vector2:
	return Vector2(global_position.x + BEAM_ORIGIN.x * facing, _beam_y)


func beam_end() -> Vector2:
	var from := beam_start()
	return Sight.first_solid(get_world_2d().direct_space_state, from, from + Vector2(beam_range * facing, 0.0))


## Height of the laser (world coordinates, for tests).
func beam_height() -> float:
	return _beam_y


func is_charging() -> bool:
	return _move == Move.CHARGE


func is_firing() -> bool:
	return _move == Move.BEAM


func is_swapping() -> bool:
	return _move == Move.SWAP


func is_enraged() -> bool:
	return _enraged


func minions() -> Array[Enemy]:
	return _minions


func _show_beam() -> void:
	if not _visual.has_method(&"show_beam"):
		return
	var state := 0
	if _move == Move.CHARGE or _move == Move.VOLLEY:
		# There is no special pose for bone shots; use the two charge frames (the bony hand glowing)
		state = 1
	elif _move == Move.BEAM:
		state = 2
	var length := absf(beam_end().x - beam_start().x) if state == 2 else 0.0
	_visual.call(&"show_beam", state, length, _beam_y - global_position.y)


## Always face the middle of the shaft (the lane on the other side): the laser sweeps across the whole shaft.
func _face_the_shaft() -> void:
	var side := signi(_lanes[1 - _lane] - global_position.x) if _move != Move.SWAP \
		else signi(_lanes[_lane] - global_position.x)
	if side != 0 and side != facing:
		facing = side
		_apply_visual_facing()


## Bob gently up and down while resting (a floating thing must not look dead).
func _hover(_delta: float) -> Vector2:
	return Vector2(0.0, 6.0 * sin(Time.get_ticks_msec() / 400.0))


## It makes no level / diagonal distinction: on screen (or within reach) it reacts, regardless of line of sight — it floats in the shaft.
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position))


## Below half health it switches gear: a sneer and a report, then shorter charges and two beams.
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= float(max_health) * enrage_below:
		_enraged = true
		_move = Move.SNEER
		_left = sneer_time
		if _visual.has_method(&"play"):
			_visual.call(&"play", &"sneer")
		GameEvents.report(&"boss_enrage", self)


## When it dies the little skulls shatter with it — **no reward**, the player did not bring them down.
func die() -> void:
	for minion in _minions:
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			minion.xp_reward = 0
			minion.money_reward = 0
			minion.die()
	_minions.clear()
	super()
