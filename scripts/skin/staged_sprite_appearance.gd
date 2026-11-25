class_name StagedSpriteAppearance
extends Appearance
## A breakable object that swaps images in stages (stage 5's gas capsules): **every chunk knocked off shows a more broken image**, so the player can see how many hits are left.
## Unlike the crate (`CrateSpriteAppearance`, darker the more it is hit, falling-apart clip when broken), this art draws each stage of damage itself:
## intact (several colours, one picked by position) → cracked → half shattered → just a ring of shards (it stays on this one once broken; the collision is gone by then).
## Gameplay only calls `show_damage(how damaged, broken or not)`, and like other traps never touches the sprites.

## The intact looks (one picked at random, worked out from the node position, so it is the same on any machine).
@export var intact: Array[Texture2D] = []
## Cracked, half shattered (switched in turn as the damage grows).
@export var cracked: Array[Texture2D] = []
## The shards left on the floor once broken.
@export var debris: Texture2D
## Where the texture's top-left corner is drawn relative to the node origin (the art is a little wider than the hitbox, shifted left by half the difference).
@export var at := Vector2.ZERO
## How many pixels it shakes sideways when hit
const SHAKE := 1.0

var _stage := 0.0
var _broken := false
var _shake := 0.0
var _pick := 0


func _ready() -> void:
	var anchor := global_position
	_pick = absi(int(anchor.x) * 7 + int(anchor.y) * 13) % maxi(1, intact.size())


func show_damage(stage: float, broken: bool) -> void:
	if stage > _stage:
		_shake = 0.12
	_stage = stage
	_broken = broken
	queue_redraw()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake -= delta
		position.x = SHAKE if int(_shake * 60.0) % 2 == 0 and _shake > 0.0 else 0.0


## Which image to draw now: 0..1 damage split evenly over "intact + each cracked image"; shards once broken.
func current() -> Texture2D:
	if _broken:
		return debris
	var steps := 1 + cracked.size()
	var step := mini(int(_stage * steps), steps - 1)
	if step == 0:
		return intact[_pick] if not intact.is_empty() else null
	return cracked[step - 1]


func _draw() -> void:
	var texture := current()
	if texture != null:
		draw_texture(texture, at)
