class_name CameraRig
extends ScreenShake
## The level camera: follows the players and **never lets a player be pushed off screen** (Contra style).
##
## It sits on the level, not on a player — in co-op both players share one camera that follows **the midpoint between them**.
## With one player the midpoint is that player, so the view is exactly as before (the old tests keep guarding that).
##
## Every physics frame does two things, in this order: first move the view to the midpoint (within the level limits),
## then clamp the living players back into view. That clamp drags whoever lags behind forward — exactly Contra's rule:
## nobody can leave their partner off screen; splitting up only works up to the edges of the view.
##
## This node's `process_physics_priority` is set very high so it runs after all players have moved.
##
## **Vertical stages (`only_up`)**: the view only scrolls up, never back down (like Contra's waterfall stage). It works by letting `limit_bottom`
## **only ever go down** — whenever the view moves up, the bottom limit tightens behind it and the engine clamps the view by itself, no separate follow code needed.
## Here the camera follows **whoever has climbed highest** instead of the midpoint: the leader climbs, the one behind falls off the bottom edge,
## which counts as falling into a pit (`main.gd`'s fall line follows the bottom of the view), and gets brought back into view (`Player.fall_out()`).

## Minimum distance between a player's body and the edge of the view (a bit more than half a body, so the whole player is visible).
const EDGE_MARGIN := 14.0
## The level's camera is in this group: bringing a player back and checking for falls both need to ask where the view is.
const GROUP := &"camera_rig"

## The view only scrolls up (vertical stages). Horizontal stages leave it false, exactly as before.
@export var only_up := false
## How much further up to look in vertical stages: the leading player sits this far **below** the middle of the view. Climbing up, you need to see what is overhead;
## at the top boss area this offset makes the level's top edge clamp the view, so **the whole boss area shows on one screen** —
## without it, with the player on the boss area floor, the view centred on them and a boss floating high left the screen (seen in a screenshot).
@export var look_ahead := 64.0


func _ready() -> void:
	super()
	add_to_group(GROUP)
	# Follow the players after their _physics_process has run, otherwise the view follows last frame's position.
	process_physics_priority = 100


## The level's camera (null if there is none, e.g. in the menu).
static func find(tree: SceneTree) -> CameraRig:
	return tree.get_first_node_in_group(GROUP) as CameraRig if tree != null else null


func _physics_process(_delta: float) -> void:
	var players := _targets()
	if players.is_empty():
		return
	global_position = _center_of(players)
	if only_up:
		global_position.y = _highest(players) - look_ahead
		# Wherever the view goes, the bottom limit follows: it can never go back
		limit_bottom = mini(limit_bottom, ceili(view_rect().end.y))
	_keep_players_on_screen(players)


## Who the camera follows: living players; if all are dead, all players (when a solo player dies the view still rests on the body, as before).
func _targets() -> Array[Player]:
	var alive: Array[Player] = []
	var all: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null:
			continue
		all.append(player)
		if player.is_alive():
			alive.append(player)
	return alive if not alive.is_empty() else all


func _center_of(players: Array[Player]) -> Vector2:
	var sum := Vector2.ZERO
	for player in players:
		sum += player.global_position
	return sum / players.size()


## Height of whoever has climbed highest (the camera follows them in vertical stages).
func _highest(players: Array[Player]) -> float:
	var top := INF
	for player in players:
		top = minf(top, player.global_position.y)
	return top


## The rectangle of the world covered by the view. Camera2D clamps the view inside its limit_* by itself; this works it out with the same rules,
## because we need to know the edges **this frame** (the real view transform only updates after the camera has moved).
func view_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / zoom
	var middle := global_position
	# When the level is narrower than the screen the clamp cannot hold, so centre the view on the level
	middle.x = clampf(middle.x, minf(limit_left + half.x, limit_right - half.x), maxf(limit_left + half.x, limit_right - half.x))
	middle.y = clampf(middle.y, minf(limit_top + half.y, limit_bottom - half.y), maxf(limit_top + half.y, limit_bottom - half.y))
	return Rect2(middle - half, half * 2.0)


func _keep_players_on_screen(players: Array[Player]) -> void:
	var view := view_rect()
	for player in players:
		if not player.is_alive():
			continue
		var spot := player.global_position
		spot.x = clampf(spot.x, view.position.x + EDGE_MARGIN, view.end.x - EDGE_MARGIN)
		if spot != player.global_position:
			player.global_position = spot
