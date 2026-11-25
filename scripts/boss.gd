class_name Boss
extends Enemy
## Base class for boss enemies. The other enemies in a level (A/B/C/D/E/turret) are regular enemies and extend Enemy directly.
##
## Differences from regular enemies:
## - **Entrance**: idle until it enters the screen (only gravity, no actions); it "appears" the first time **any part** of its body is on screen —
## (going by the centre point, a wide boss would already be half visible and hittable while still idling.
## Getting hit while idle also makes it appear at once, so it cannot be shot for free before it wakes.)
## Reports appear_event (special sound) and notifies the HUD through GameEvents.boss_appeared to show the portrait and health bar. Appears only once.
## - **Ultimate**: the freeze and bullet clearing work on bosses too (the whole tree pauses, boss bullets are in the enemy_bullets group),
## but a boss is not destroyed outright; it takes ultimate_damage() = max health × ultimate_damage_ratio (it still dies if that is more than it has left).
## - Health changes emit health_changed, which the HUD bar listens to.
##
## Each boss's attacks live in its subclass's _boss_process(); every boss is different.

## Health changed (including the moment it appears); the HUD bar listens to this.
signal health_changed(health: int, max_health: int)

## Name (for the HUD and cutscenes later).
@export var display_name := "BOSS"
## Portrait in the HUD (placeholder art lives in skins/default/portraits/). If the pack's appearance has a portrait, that one is used; see hud_portrait().
@export var portrait: Texture2D
## Share of max health taken by one hit of the ultimate (0.25 = a quarter, dead in 4). Can differ per boss.
@export_range(0.0, 1.0) var ultimate_damage_ratio := 0.25
## Event reported on entrance (the pack looks up a sound by it).
@export var appear_event := &"boss_appear"
## Whether killing it clears the stage (2026-11, off for stage 5's mid-level boss): the level only listens for the deaths of the ones that do.
## Health bar, portrait and "the ultimate only deals damage" work the same for both.
@export var ends_level := true

var has_appeared := false


func _physics_process(delta: float) -> void:
	if not has_appeared:
		_apply_gravity(delta)
		move_and_slide()
		if is_partly_on_screen():
			appear()
		return
	_boss_process(delta)


## Subclasses put their behaviour here (called every physics frame after the entrance).
func _boss_process(_delta: float) -> void:
	pass


## Entrance: happens only once. Normally triggered by entering the screen; a scripted level can call it directly.
func appear() -> void:
	if has_appeared:
		return
	has_appeared = true
	GameEvents.report(appear_event, self)
	GameEvents.boss_appeared.emit(self)
	health_changed.emit(health, max_health)


func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	if health <= 0:
		return
	appear()
	super.take_damage(amount, source_position, from)
	health_changed.emit(maxi(health, 0), max_health)


## Damage of one ultimate hit (rounded up, at least 1).
func ultimate_damage() -> int:
	return maxi(1, ceili(max_health * ultimate_damage_ratio))


## The ultimate only damages a boss, it never destroys it outright.
func hit_by_ultimate(from: Node = null) -> void:
	take_damage(ultimate_damage(), Vector2.INF, from)


## Portrait shown in the HUD: if the appearance (pack) brings its own, use that, so the portrait follows the skin; otherwise the placeholder set in the scene.
func hud_portrait() -> Texture2D:
	var skinned: Variant = _visual.get(&"portrait") if _visual != null else null
	return skinned if skinned is Texture2D else portrait
