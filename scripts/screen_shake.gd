class_name ScreenShake
extends Camera2D
## Screen shake: like `Fx` and `Sfx` it listens on the event bus and decides how hard to shake by event name.
##
## Only the camera's `offset` changes, not the position following the player nor the level limits, so it returns to rest by itself.
## Every frame it offsets by a fixed amount in a random direction, rounded to whole pixels — on a 320×180 pixel image, half-pixel shake only blurs the picture.

## How many pixels each event shakes. The player's own shots shake only a little; explosions and the ultimate the most.
const SHAKES := {
	&"player_shoot": 1.2,
	&"player_hurt": 4.0,
	&"player_death": 6.0,
	&"enemy_death": 2.0,
	&"explosion": 6.0,
	&"boss_appear": 4.0,
	&"boss_enrage": 4.0,
	&"ultimate_start": 5.0,
	&"ultimate_blast": 8.0,
}

## Overall strength multiplier: turn it down if playtesters feel queasy; 0 means no shaking at all.
@export var strength_scale := 1.0
## Pixels of decay per second (larger stops sooner).
@export var decay := 28.0

var _strength := 0.0


func _ready() -> void:
	# The whole tree is paused when the ultimate fires, and that shake must still be visible.
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.event_happened.connect(_on_event)


func _on_event(event: StringName, _source: Node) -> void:
	if SHAKES.has(event):
		shake(SHAKES[event])


## Shake by amount pixels. If a stronger shake is already running keep it; a small shake must not cut off a big one.
func shake(amount: float) -> void:
	_strength = maxf(_strength, amount * strength_scale)


func _process(delta: float) -> void:
	if _strength <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_strength = move_toward(_strength, 0.0, decay * delta)
	# Random direction, fixed amplitude: with each component random on its own, a good share of frames would round to (0, 0) and the shake would leak away frame by frame.
	offset = (Vector2.from_angle(randf() * TAU) * _strength).round()
