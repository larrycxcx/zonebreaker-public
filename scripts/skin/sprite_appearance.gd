class_name SpriteAppearance
extends Appearance
## Sprite version of the look: one image for the body and one for arms plus gun, stacked.
##
## The sprites are generated from the original art pack by `tools/skin_build.py`; every clip and every aim direction has **a left-facing and a right-facing set**,
## with both sets' anchors on the same pixel, so turning around just swaps the texture — no `flip_h`,
## and certainly no negative `scale` (a negative scale makes the engine cull the character wrongly, see the pitfalls in CLAUDE.md).
##
## This only handles the picture. All hit points are on the character's body, and the game rules are the same with or without this look
## (`tests/test_skin_visuals.gd` compares it item by item with the placeholder blocks).

## Size of a frame and the **anchor** (the pixel in the frame matching the character's body origin).
## These three numbers are set by `tools/skin_build.py`, and both sides must agree — change them there and you change them here.
## The left-facing set is mirrored around the ANCHOR_X column, so turning around never moves a node.
const FRAME_SIZE := 56
const ANCHOR_X := 28
const ANCHOR_Y := 40

## Playback speed of body clips (frames / second). Clips not listed are single frames and do not play.
const BODY_FPS := {
	&"idle": 6.0,
	&"walk": 10.0,
	&"run": 14.0,
	&"crawl": 8.0,
	&"climb": 8.0,
}
## The gun used when the gun in hand has no sprites of its own (`Weapon.look` empty, or this skin did not draw that gun).
const DEFAULT_LOOK := &"rifle"

## Playback speed of the death clip: it plays once and holds the last frame (lying on the ground).
const DEATH_FPS := 10.0

## Aim direction → name of the arm sprite. The keys follow the same scheme as `Appearance.GUN_BY_AIM` (absolute x, sign of y).
const ARMS_BY_AIM := {
	Vector2(0, -1): &"up",
	Vector2(1, -1): &"diag_up",
	Vector2(1, 0): &"level",
	Vector2(1, 1): &"diag_down",
	Vector2(0, 1): &"down",
}

## Motion → name of the body sprite. Rising and falling in the air share one two-frame image, picking the frame by state.
const BODY_BY_MOTION := {
	Motion.IDLE: &"idle",
	Motion.WALK: &"walk",
	Motion.RUN: &"run",
	Motion.JUMP: &"air",
	Motion.FALL: &"air",
	Motion.CLIMB: &"climb",
	Motion.HANG: &"climb",
}

## Which folder the sprites live in; file names look like `body_walk_r.png` / `arms_level_l.png`.
@export_dir var art_dir := "res://skins/cyberpunk/player"

@onready var _body: Sprite2D = $Body
@onready var _arms: Sprite2D = $Arms

var _motion := Motion.IDLE
var _crouched := false
var _elapsed := 0.0
var _dead := false
var _dead_since := 0.0
## Climbing a ladder: the clip only advances while actually climbing; stopped on the ladder it holds the current frame (`_climb_time` only runs while climbing).
var _climb_time := 0.0
var _look := DEFAULT_LOOK


func _ready() -> void:
	# No super(): the base class flips by mirroring child positions, which is for the placeholder blocks; this flips by swapping textures.
	# The texture is drawn centred, then moved up so the anchor pixel lands exactly on the character's body origin.
	var offset := Vector2(FRAME_SIZE / 2.0 - ANCHOR_X, FRAME_SIZE / 2.0 - ANCHOR_Y)
	for sprite: Sprite2D in [_body, _arms]:
		sprite.centered = true
		sprite.offset = offset
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _motion == Motion.CLIMB:
		_climb_time += delta
	_advance()


## Turning around: switch to the other side's set. Child positions are not mirrored and scale is not touched.
func face(facing: int) -> void:
	if facing == _facing:
		return
	_facing = facing
	_refresh()


## Switching guns: the whole set of arm sprites becomes this gun's (`arms_<look>_<direction>_<facing>.png`).
func hold(look: StringName) -> void:
	var wanted := look if look != &"" else DEFAULT_LOOK
	if wanted == _look:
		return
	_look = wanted
	_refresh()


## Which gun's sprites are shown now (for tests): the fallback gun when this gun has no sprites.
func held_look() -> StringName:
	return _look if ResourceLoader.exists(_arms_path(_look, &"level", &"r")) else DEFAULT_LOOK


func aim(direction: Vector2) -> void:
	if direction == Vector2.ZERO or direction == _aim:
		return
	_aim = direction
	_refresh()


## Prone or not. The sprites have a dedicated prone pose; no squashing and no moving down (that image's own feet stay in place).
func pose(height_ratio: float, _lowered: float) -> void:
	var crouched := height_ratio < 1.0
	if crouched == _crouched:
		return
	_crouched = crouched
	_refresh()


func motion(state: Motion) -> void:
	if state == _motion:
		return
	_motion = state
	_refresh()


## Dead: play the fall once and hold the last frame. Not darkened like the placeholder blocks — lying on the ground says it all.
## In the death clip the character is empty-handed (the gun has dropped), so the arms image is hidden entirely.
func show_dead() -> void:
	if _dead:
		return
	_dead = true
	_dead_since = _elapsed
	_refresh()


## Back on its feet: the death clip was holding its last frame; switch back to the normal clips here.
func revive() -> void:
	if not _dead:
		return
	_dead = false
	_refresh()


## The body sprite name for the current frame (for tests). Death beats everything (dying prone or in the air falls the same way).
## When prone: still uses the static frame, moving plays the crawl (walking and running both count as moving — you cannot run while prone anyway).
func body_clip() -> StringName:
	if _dead:
		return &"death"
	if _crouched:
		return &"crawl" if _motion == Motion.WALK or _motion == Motion.RUN else &"crouch"
	return BODY_BY_MOTION[_motion]


## The arm sprite name for the current frame; no arms while prone, dead or climbing (those body images come with arms — the climb is seen from behind, both hands on the ladder).
func arms_clip() -> StringName:
	if _crouched or _dead or _motion == Motion.CLIMB or _motion == Motion.HANG:
		return &""
	return ARMS_BY_AIM.get(Vector2(absf(signf(_aim.x)), signf(_aim.y)), &"level")


func _refresh() -> void:
	if _body == null:
		return # Gameplay may call in before _ready, when @onready has not been assigned yet; refresh once in _ready to catch up
	var side := &"r" if _facing >= 0 else &"l"
	_put(_body, "body_%s_%s" % [body_clip(), side])
	var arms := arms_clip()
	_arms.visible = arms != &""
	if _arms.visible:
		_put(_arms, _arms_path(held_look(), arms, side).get_file().get_basename())
	_advance()


func _arms_path(look: StringName, aim_clip: StringName, side: StringName) -> String:
	return "%s/arms_%s_%s_%s.png" % [art_dir, look, aim_clip, side]


## Swap the texture and work out the frame count from the image width (every frame is square).
func _put(sprite: Sprite2D, file: String) -> void:
	var texture: Texture2D = load("%s/%s.png" % [art_dir, file])
	if texture == null:
		push_warning("missing skin sprite: %s/%s.png" % [art_dir, file])
		return
	sprite.texture = texture
	sprite.hframes = maxi(1, texture.get_width() / texture.get_height())


## Advance the body clip with time; the two air frames are picked by rising / falling, not played by time.
func _advance() -> void:
	if _body == null or _body.texture == null:
		return
	if _dead:
		_body.frame = mini(int((_elapsed - _dead_since) * DEATH_FPS), _body.hframes - 1)
		return
	if _motion == Motion.FALL and not _crouched:
		_body.frame = mini(1, _body.hframes - 1)
		return
	if (_motion == Motion.CLIMB or _motion == Motion.HANG) and not _crouched:
		_body.frame = int(_climb_time * BODY_FPS[&"climb"]) % _body.hframes
		return
	var fps: float = BODY_FPS.get(body_clip(), 0.0)
	_body.frame = int(_elapsed * fps) % _body.hframes if fps > 0.0 else 0
