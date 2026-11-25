class_name EnemyMutant
extends EnemyHammer
## Stage 5's mutant (5-C, also what the scientists turn into): walks up, raises its fists and **slams the ground**.
##
## Besides the hammer man's "hit around the hammer head", the slam sends out a **shockwave**: players within `shock_radius` left and right,
## **with their feet on the ground** and on the same layer (feet within `shock_height` of its own) all take a hit and are bounced upward.
## **Jumping dodges it** (players in the air are not affected) — the raised fists are your cue to jump.
## Walking up, turning, winding up and damage on the frame the slam lands all come from `EnemyHammer` (`hit_frame` set to frame 4 of the art).

@export_group("Shockwave")
@export var shock_radius := 72.0
@export var shock_height := 20.0
@export var shock_damage := 24
## How hard the shockwave throws you (upward).
@export var shock_lift := 260.0


func _land_the_blow() -> void:
	var direct: Array[Player] = []
	var at := smash_point()
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= smash_radius:
			direct.append(player)
	super()
	var feet := global_position.y + feet_offset()
	for player in players_by_distance():
		if direct.has(player) or not shaken(player, feet):
			continue
		var landed := not player.is_invincible()
		player.take_damage(roundi(shock_damage * Stage.damage_scale()), global_position, self)
		if landed:
			player.shove(Vector2(0.0, -shock_lift))


## Does the shockwave reach this player: within range left and right, feet on the ground, at about the height of its feet.
func shaken(player: Player, feet: float) -> bool:
	if not player.is_on_floor():
		return false
	if absf(player.global_position.x - global_position.x) > shock_radius:
		return false
	return absf(player.global_position.y + 16.0 - feet) <= shock_height


## How far below the origin its own feet are (bottom of the hitbox).
func feet_offset() -> float:
	return 16.0
