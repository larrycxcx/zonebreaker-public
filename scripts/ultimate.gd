class_name Ultimate
extends Node2D
## The effect of the ultimate (instant; fired from the weapon slot of weapons/ultimate.tres, so charges and cooldown go through the weapon system).
##
## The moment it fires: clear every enemy bullet, note the enemies on screen right now, make the players invincible, then pause the whole scene tree —
## players, enemies and bullets all freeze for freeze_time seconds. When the time is up it resumes and calls hit_by_ultimate() on the enemies noted earlier:
## ordinary enemies are destroyed outright (regardless of health), bosses only take damage (Boss.ultimate_damage) and are never destroyed outright.
## Enemies off screen are unaffected. Future animation goes here; the node is set to PROCESS_MODE_ALWAYS so it keeps playing during the pause.
## The visuals are not its job: when the freeze ends and ultimate_blast is reported, `targets` holds the enemies to be hit (not destroyed yet),
## and Fx draws an explosion on each of them from it.

## How long the freeze lasts (seconds).
@export var freeze_time := 2.0
## Extra invincibility for the players after action resumes (seconds), so an off-screen enemy does not happen to hit them right then.
@export var grace_time := 0.5
## Size of the explosion drawn on each enemy (display only, read by Fx; the same size as a grenade's).
@export var blast_radius := 56.0

## The enemies this blast hits: the ones on screen when it fires; Fx reads it to draw explosions when ultimate_blast is reported at the end of the freeze.
var targets: Array[Enemy] = []

## Group of enemy bullets (set in enemy_bullet.tscn).
const ENEMY_BULLETS := &"enemy_bullets"


## Who fired it (filled in by the weapon slot). Enemies destroyed by it reward this player.
var shooter: Node


## Called by the weapon slot when firing; the ultimate has no direction.
func launch(_direction: Vector2) -> void:
	pass


## Ultimates currently freezing the game are in this group. The pause menu uses it to know "the ultimate is freezing things right now, do not interfere".
const GROUP := &"ultimates"


func _ready() -> void:
	# The whole tree gets paused; this node has to keep running to resume things when the time is up.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_activate()


func _activate() -> void:
	var tree := get_tree()
	targets = enemies_on_screen()
	for bullet in tree.get_nodes_in_group(ENEMY_BULLETS):
		bullet.queue_free()
	# Every player is frozen, so every player gets invincibility (the partner too in co-op).
	# The players' own timers also stop during the pause, so this invincibility covers the whole freeze and lasts grace_time after it.
	for node in tree.get_nodes_in_group(&"player"):
		(node as Player).grant_invincibility(grace_time)
	tree.paused = true
	await tree.create_timer(freeze_time, true).timeout
	tree.paused = false
	GameEvents.report(&"ultimate_blast", self)
	for enemy in targets:
		if is_instance_valid(enemy) and enemy.health > 0:
			enemy.hit_by_ultimate(shooter)
	queue_free()


## Enemies whose body centre is inside the visible screen right now.
func enemies_on_screen() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy != null and enemy.health > 0 and enemy.is_on_screen():
			found.append(enemy)
	return found
