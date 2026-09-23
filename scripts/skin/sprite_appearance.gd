class_name SpriteAppearance
extends Appearance
## 精灵图版的外观：身体一张图、手臂加枪一张图，两张叠在一起。
##
## 贴图由 `tools/skin_build.py` 从原始素材包生成，每个动作、每个瞄准方向都有**朝左朝右两套**，
## 两套图的锚点落在同一个像素上，所以转身只是换一张贴图——不用 `flip_h`，
## 更不用负的 `scale`（负 scale 会让角色被引擎错误剔除，见 CLAUDE.md 里踩过的坑）。
##
## 这里只管画面。判定点全在角色本体上，换不换这套外观游戏规则都一样
## （`tests/test_skin_visuals.gd` 拿它和占位方块逐项对过）。

## 贴图每帧的边长，和**锚点**（帧里对应角色身体原点的那个像素）。
## 这三个数由 `tools/skin_build.py` 决定，两边必须一致——改了那边就要改这里。
## 朝左那套图是按 ANCHOR_X 那一列镜像出来的，所以转身不需要动节点。
const FRAME_SIZE := 56
const ANCHOR_X := 28
const ANCHOR_Y := 40

## 身体动画的播放速度（帧/秒）。没列的是单帧，不用播。
const BODY_FPS := {
	&"idle": 6.0,
	&"walk": 10.0,
	&"run": 14.0,
	&"crawl": 8.0,
}
## 手里的枪没有专门的贴图时（`Weapon.look` 留空，或者这套皮肤没画这把枪）就用这一把。
const DEFAULT_LOOK := &"rifle"

## 死亡动画的播放速度：只播一遍，播完停在最后一帧（躺在地上）。
const DEATH_FPS := 10.0

## 瞄准方向 → 手臂贴图的名字。键和 `Appearance.GUN_BY_AIM` 用的是同一套（x 取绝对值、y 取符号）。
const ARMS_BY_AIM := {
	Vector2(0, -1): &"up",
	Vector2(1, -1): &"diag_up",
	Vector2(1, 0): &"level",
	Vector2(1, 1): &"diag_down",
	Vector2(0, 1): &"down",
}

## 动作 → 身体贴图的名字。空中上升和下落共用一张两帧的图，按状态取第几帧。
const BODY_BY_MOTION := {
	Motion.IDLE: &"idle",
	Motion.WALK: &"walk",
	Motion.RUN: &"run",
	Motion.JUMP: &"air",
	Motion.FALL: &"air",
}

## 贴图放在哪个目录下，文件名形如 `body_walk_r.png` / `arms_level_l.png`。
@export_dir var art_dir := "res://skins/cyberpunk/player"

@onready var _body: Sprite2D = $Body
@onready var _arms: Sprite2D = $Arms

var _motion := Motion.IDLE
var _crouched := false
var _elapsed := 0.0
var _dead := false
var _dead_since := 0.0
var _look := DEFAULT_LOOK


func _ready() -> void:
	# 不调 super()：基类那套按位置镜像子节点的翻转法是给占位方块用的，这里靠换贴图翻转。
	# 贴图居中画，再往上挪，让锚点那个像素正好落在角色的身体原点上。
	var offset := Vector2(FRAME_SIZE / 2.0 - ANCHOR_X, FRAME_SIZE / 2.0 - ANCHOR_Y)
	for sprite: Sprite2D in [_body, _arms]:
		sprite.centered = true
		sprite.offset = offset
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	_advance()


## 转身：换成另一边那套贴图。不镜像子节点的位置，也不动 scale。
func face(facing: int) -> void:
	if facing == _facing:
		return
	_facing = facing
	_refresh()


## 换枪：整套手臂贴图换成这把枪的（`arms_<look>_<方向>_<朝向>.png`）。
func hold(look: StringName) -> void:
	var wanted := look if look != &"" else DEFAULT_LOOK
	if wanted == _look:
		return
	_look = wanted
	_refresh()


## 现在显示的是哪把枪的贴图（测试用）：没有这把枪的贴图时是回落后的那把。
func held_look() -> StringName:
	return _look if ResourceLoader.exists(_arms_path(_look, &"level", &"r")) else DEFAULT_LOOK


func aim(direction: Vector2) -> void:
	if direction == Vector2.ZERO or direction == _aim:
		return
	_aim = direction
	_refresh()


## 趴下与否。精灵图有专门的趴姿，不压扁、也不整体下移（那张图自己的脚底就在原地）。
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


## 死了：播一遍倒地动画，停在最后一帧。不像占位方块那样变暗——倒在地上本身就说明白了。
## 死亡动画里人是空手的（枪脱手了），所以手臂那张图整个藏起来。
func show_dead() -> void:
	if _dead:
		return
	_dead = true
	_dead_since = _elapsed
	_refresh()


## 又站起来了：倒地那组停在最后一帧，这里换回正常的动作。
func revive() -> void:
	if not _dead:
		return
	_dead = false
	_refresh()


## 当前这一帧身体用的贴图名（测试用）。死亡优先于一切（趴着、在空中被打死都一样倒）。
## 趴着时：不动用静止那一帧，在挪就播爬行（走和跑都算挪——趴着本来也跑不起来）。
func body_clip() -> StringName:
	if _dead:
		return &"death"
	if _crouched:
		return &"crawl" if _motion == Motion.WALK or _motion == Motion.RUN else &"crouch"
	return BODY_BY_MOTION[_motion]


## 当前这一帧手臂用的贴图名；趴下和死亡时没有手臂（那两套身体图自带手臂）。
func arms_clip() -> StringName:
	if _crouched or _dead:
		return &""
	return ARMS_BY_AIM.get(Vector2(absf(signf(_aim.x)), signf(_aim.y)), &"level")


func _refresh() -> void:
	if _body == null:
		return # _ready 之前玩法就可能调过来，那时 @onready 还没赋值，等 _ready 里统一刷一次
	var side := &"r" if _facing >= 0 else &"l"
	_put(_body, "body_%s_%s" % [body_clip(), side])
	var arms := arms_clip()
	_arms.visible = arms != &""
	if _arms.visible:
		_put(_arms, _arms_path(held_look(), arms, side).get_file().get_basename())
	_advance()


func _arms_path(look: StringName, aim_clip: StringName, side: StringName) -> String:
	return "%s/arms_%s_%s_%s.png" % [art_dir, look, aim_clip, side]


## 换贴图并按图宽算出有几帧（每帧都是正方形）。
func _put(sprite: Sprite2D, file: String) -> void:
	var texture: Texture2D = load("%s/%s.png" % [art_dir, file])
	if texture == null:
		push_warning("皮肤贴图缺失：%s/%s.png" % [art_dir, file])
		return
	sprite.texture = texture
	sprite.hframes = maxi(1, texture.get_width() / texture.get_height())


## 按时间推进身体动画；空中那两帧按上升/下落取，不按时间播。
func _advance() -> void:
	if _body == null or _body.texture == null:
		return
	if _dead:
		_body.frame = mini(int((_elapsed - _dead_since) * DEATH_FPS), _body.hframes - 1)
		return
	if _motion == Motion.FALL and not _crouched:
		_body.frame = mini(1, _body.hframes - 1)
		return
	var fps: float = BODY_FPS.get(body_clip(), 0.0)
	_body.frame = int(_elapsed * fps) % _body.hframes if fps > 0.0 else 0
