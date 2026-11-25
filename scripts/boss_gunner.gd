class_name BossGunner
extends Boss
## Stage 5's **mid-level boss**, the "mutant gunner" (art `lab-tileset/boss/1`). Agreed with the user in 2026-11:
## it waits in a gated room in the middle of the stage; **killing it does not clear the stage** (`ends_level` is off), it opens the door ahead.
##
## Its moves come **in a fixed order** (`ROTATION`): charged laser → laser bolts fired while walking → rifle-butt lunge;
## when the player gets within `kick_range` it slips in a **front kick** (knocks them away).
## 1. **Charged laser**: stands still, plays the charge frames (`charge_time`, the warning), then fires a level beam **that stops at the first wall** (`Sight.first_solid`;
## one-way platforms do not block it) at chest height — **lying prone dodges it** (the same rule as "standing shots fly over prone targets").
## 2. **Laser bolts**: walks toward the player firing a burst (the base class burst, `bullet_scene`).
## 3. **Rifle-butt lunge**: crouches to wind up (`lunge_windup`), then rushes forward (`lunge_speed` × `lunge_time`); contact hurts.
## **Below half health**: faster rhythm (`enrage_rush`) and the charged laser becomes **two beams** — first at chest height (dodge prone), then it **hops in place**
## (`hop_height`) and fires a second level beam from the top of the hop, about 50 above the floor: it clears a standing player's head but hits a jumper,
## so you cannot just stay prone. The art has no raised-gun pose, so the high beam comes from "the gunner hopping up" and still leaves the muzzle; the hop is also the warning.
## `boss_enrage` is reported only once.
## It does not leave its home ground (`roam_range` around where it spawned); the room is its ground.

enum Move { IDLE, CHARGE, BEAM, BOLTS, LUNGE_WINDUP, LUNGE, KICK, HOP }

const ROTATION := [Move.CHARGE, Move.BOLTS, Move.LUNGE_WINDUP]

@export_group("Arena")
@export var roam_range := 200.0
@export var walk_speed := 70.0
@export var keep_distance := 180.0

@export_group("Laser")
@export var charge_time := 0.7
@export var beam_time := 0.45
@export var beam_damage := 52
@export var beam_range := 640.0
## Half thickness of the beam (the hit check is a horizontal band).
@export var beam_half := 3.0
## How far below the origin the first beam is (negative = higher): in the art the beam is on rows 41~45 and the origin on row 48 → 5 up, about 29 above the floor (chest).
@export var beam_low := -5.0
## How high it hops before the second beam in phase 2: fired from the top, the beam is about 29 + 21 = 50 above the floor (just over a standing head, right where a jump goes).
@export var hop_height := 21.0

@export_group("Bolts")
@export var bolt_time := 1.6

@export_group("Lunge")
@export var lunge_windup := 0.45
@export var lunge_speed := 320.0
@export var lunge_time := 0.35
@export var lunge_damage := 48

@export_group("Kick")
@export var kick_range := 44.0
@export var kick_time := 0.5
@export var kick_hit_at := 0.25
@export var kick_damage := 40
@export var kick_push := Vector2(520, -200)

@export_group("Rage")
@export_range(0.0, 1.0) var enrage_below := 0.5
@export var enrage_rush := 0.7
@export var rest_time := 0.8

## Where the beam comes out (relative to the origin, facing right): the muzzle.
const BEAM_ORIGIN := Vector2(36, 0)

var move := Move.IDLE
var _left := 0.0
var _turn := 0
var _beams_left := 0
var _beam_y := 0.0
var _kicked := false
var _enraged := false
var _home := Vector2.ZERO
var _lunge_hit := false
## Hovering at the top of the hop (no gravity) while firing the second beam; it drops once done.
var _hovering := false


var _homed := false


func _boss_process(delta: float) -> void:
	# The centre of its ground is taken on its first action (wherever it stands when it appears; also right for ones placed after spawning)
	if not _homed:
		_homed = true
		_home = global_position
	_apply_gravity(delta)
	var target := _nearest()
	match move:
		Move.IDLE:
			_left -= delta
			_face(target)
			velocity.x = 0.0
			if target != null and _close(target, kick_range):
				_start(Move.KICK)
			elif _left <= 0.0 and target != null:
				_start(ROTATION[_turn % ROTATION.size()])
				_turn += 1
		Move.CHARGE:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_start(Move.BEAM)
		Move.BEAM:
			velocity.x = 0.0
			if _hovering:
				velocity.y = 0.0
			_left -= delta
			_burn()
			if _left <= 0.0:
				_beams_left -= 1
				_hovering = false
				if _beams_left > 0:
					# Second beam of phase 2: hop first, fire from the top
					move = Move.HOP
					velocity.y = -sqrt(2.0 * gravity * hop_height)
					_show_beam()
				else:
					_rest()
		Move.HOP:
			velocity.x = 0.0
			if velocity.y >= 0.0:
				move = Move.BEAM
				_left = beam_time
				_hovering = true
				velocity.y = 0.0
				_beam_y = global_position.y + beam_low
		Move.BOLTS:
			_left -= delta
			_face(target)
			var gap := absf(target.global_position.x - global_position.x) if target != null else 0.0
			velocity.x = walk_speed * facing if gap > keep_distance else 0.0
			try_shoot(delta, update_aim(delta, target))
			if _left <= 0.0:
				_rest()
		Move.LUNGE_WINDUP:
			velocity.x = 0.0
			_left -= delta
			if _left <= 0.0:
				_start(Move.LUNGE)
		Move.LUNGE:
			_left -= delta
			velocity.x = lunge_speed * facing
			_lunge_contact()
			if _left <= 0.0:
				_rest()
		Move.KICK:
			velocity.x = 0.0
			_left -= delta
			if not _kicked and kick_time - _left >= kick_hit_at:
				_kicked = true
				_land_kick()
			if _left <= 0.0:
				_rest()
	_stay_home()
	move_and_slide()
	# The lunge covers 5 pixels a frame; if it stops a little past the line, clamp it back
	global_position.x = clampf(global_position.x, _home.x - roam_range, _home.x + roam_range)


func _start(next: Move) -> void:
	move = next
	var rush := enrage_rush if _enraged else 1.0
	match next:
		Move.CHARGE:
			_left = charge_time * rush
			_play(&"charge")
		Move.BEAM:
			_left = beam_time
			_beams_left = 2 if _enraged else 1
			_beam_y = global_position.y + beam_low
			_play(&"beam")
		Move.BOLTS:
			_left = bolt_time
		Move.LUNGE_WINDUP:
			_left = lunge_windup * rush
			_play(&"lunge")
		Move.LUNGE:
			_left = lunge_time
			_lunge_hit = false
		Move.KICK:
			_left = kick_time
			_kicked = false
			_play(&"kick")
	_show_beam()


func _rest() -> void:
	move = Move.IDLE
	_left = rest_time * (enrage_rush if _enraged else 1.0)
	_show_beam()


func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	super(amount, source_position, from)
	if not _enraged and health > 0 and float(health) <= max_health * enrage_below:
		_enraged = true
		GameEvents.report(&"boss_enrage", self)


## While the beam is on: everyone whose body touches the band takes a hit (invincibility frames stop a second hit from the same beam).
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
	_show_beam()


func beam_start() -> Vector2:
	return Vector2(global_position.x + BEAM_ORIGIN.x * facing, _beam_y)


func beam_end() -> Vector2:
	var from := beam_start()
	return Sight.first_solid(get_world_2d().direct_space_state, from, from + Vector2(beam_range * facing, 0.0))


func _lunge_contact() -> void:
	if _lunge_hit:
		return
	var reach := Rect2(global_position + Vector2(-16.0 + 12.0 * facing, -24.0), Vector2(32, 48))
	for player in players_by_distance():
		if reach.intersects(player.hit_box()):
			_lunge_hit = true
			player.take_damage(roundi(lunge_damage * Stage.damage_scale()), global_position, self)


func _land_kick() -> void:
	for player in players_by_distance():
		if _close(player, kick_range + 8.0):
			var landed := not player.is_invincible()
			player.take_damage(roundi(kick_damage * Stage.damage_scale()), global_position, self)
			if landed:
				player.shove(Vector2(kick_push.x * facing, kick_push.y))


## Stays on its own ground: stops at the edge (a lunge stops at the edge too).
func _stay_home() -> void:
	var low := _home.x - roam_range
	var high := _home.x + roam_range
	if (global_position.x <= low and velocity.x < 0.0) or (global_position.x >= high and velocity.x > 0.0):
		velocity.x = 0.0


func _nearest() -> Player:
	var players := players_by_distance()
	return players[0] if not players.is_empty() else null


func _close(player: Player, distance: float) -> bool:
	return absf(player.global_position.x - global_position.x) <= distance \
		and absf(player.global_position.y - global_position.y) <= 40.0


func _face(target: Node2D) -> void:
	if target == null:
		return
	var side := signi(target.global_position.x - global_position.x)
	if side != 0 and side != facing:
		facing = side
		_apply_visual_facing()


func _play(clip: StringName) -> void:
	if _visual != null and _visual.has_method(&"play"):
		_visual.call(&"play", clip)


func _show_beam() -> void:
	if _visual == null or not _visual.has_method(&"show_beam"):
		return
	var state := 0
	if move == Move.CHARGE or move == Move.HOP:
		state = 1
	elif move == Move.BEAM:
		state = 2
	var length := absf(beam_end().x - beam_start().x) if state == 2 else 0.0
	_visual.call(&"show_beam", state, length, _beam_y - global_position.y)


func is_charging() -> bool:
	return move == Move.CHARGE


func is_firing() -> bool:
	return move == Move.BEAM


func is_enraged() -> bool:
	return _enraged


func beam_height() -> float:
	return _beam_y
