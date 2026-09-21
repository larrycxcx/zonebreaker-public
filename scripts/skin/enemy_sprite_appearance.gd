class_name EnemySpriteAppearance
extends Appearance
## 精灵图版的敌人外观：一整张图（枪画在身上），按状态挑动作。
##
## 贴图由 `tools/enemy_build.py` 生成：每个动作一条横排的帧（`<动作>_r.png` / `<动作>_l.png`），
## 朝左那套按锚点镜像好了，所以转身只是换贴图——不用 flip_h，更不用负 scale。
## 和玩家的 SpriteAppearance 一样只管画面：判定点在敌人本体上，换不换这套外观规则都一样。
##
## 挑哪个动作（优先级从高到低）：
##   死了 → death（播一遍停住）
##   正在播的一次性动作 → fire() 的开火、flash_hit() 的受伤
##   趴着 → prone 第 1 帧（开火时整组播一遍）
##   斜着瞄准 → attack_up / attack_down 第 1 帧（举着枪等开火；E 一直朝正下方，那不算「斜着」）
##   在走 → walk；站着 → idle

## 地面敌人每帧的大小和锚点（帧里对应敌人身体原点的那个像素），必须和 tools/enemy_build.py 一致。
## 比玩家的帧宽：倒地时人扑在身前，56 宽装不下。飞的 E 不一样，在它自己的场景里改 frame_size / anchor。
const FRAME_W := 80
const FRAME_H := 56
const ANCHOR_X := 40
const ANCHOR_Y := 40

## 循环动作的速度（帧/秒）。
const LOOP_FPS := {&"idle": 6.0, &"walk": 10.0}
## 一次性动作的速度。
const ONCE_FPS := 12.0
## 倒地播完后在地上躺多久、再用多久淡出。
const CORPSE_STAY := 0.4
const CORPSE_FADE := 0.4

## 瞄准方向 → 开火动作的名字。
const ATTACK_BY_AIM := {
	Vector2(1, 0): &"attack_level",
	Vector2(1, -1): &"attack_up",
	Vector2(1, 1): &"attack_down",
	Vector2(0, 1): &"attack_down", # E 竖直向下开火
}

## 贴图放在哪个目录下。三种巡逻兵用同一个脚本，只是这个目录不同（换色版）。
@export_dir var art_dir := "res://skins/cyberpunk/enemies/walker_a"
## 这套贴图每帧多大、锚点在哪（生成脚本定的，场景里照抄）。
@export var frame_size := Vector2i(FRAME_W, FRAME_H)
@export var anchor := Vector2i(ANCHOR_X, ANCHOR_Y)

@onready var _body: Sprite2D = $Body

var _motion := Motion.IDLE
var _prone := false
var _dead := false
var _elapsed := 0.0
## 正在播的一次性动作（开火、受伤）和它从什么时候开始；空表示没有。
var _once := &""
var _once_since := 0.0
var _dead_since := 0.0


func _ready() -> void:
	# 不调 super()：基类那套按位置镜像子节点的翻转法是给占位方块用的，这里靠换贴图翻转。
	_body.centered = true
	_body.offset = Vector2(frame_size) / 2.0 - Vector2(anchor)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _once != &"" and not _dead and _body.texture != null \
			and (_elapsed - _once_since) * ONCE_FPS >= _body.hframes:
		_once = &""
		_refresh()
		return
	_advance()


func face(facing: int) -> void:
	if facing == _facing:
		return
	_facing = facing
	_refresh()


func aim(direction: Vector2) -> void:
	if direction == Vector2.ZERO or direction == _aim:
		return
	_aim = direction
	_refresh()


func motion(state: Motion) -> void:
	if state == _motion:
		return
	_motion = state
	_refresh()


## 趴下与否。有专门的趴姿，不压扁、不整体下移。
func pose(height_ratio: float, _lowered: float) -> void:
	var prone := height_ratio < 1.0
	if prone == _prone:
		return
	_prone = prone
	_once = &""
	_refresh()


## 开一枪：按现在的姿势播一遍开火动作（趴着就是趴着开火那组）。
func fire() -> void:
	_play_once(&"prone" if _prone else _attack_clip())


## 挨了一下：播一遍受伤（素材的第 2 帧是整个人闪红）。
func flash_hit() -> void:
	_play_once(&"hurt")


## 死了：本体马上会被删掉，所以外观把自己挪到特效层下面，播完倒地、躺一会儿、淡出后自己消失。
## 特效层不在（比如测试把它删了）就挂到敌人的父节点下，效果一样。
func show_dead() -> void:
	if _dead:
		return
	_dead = true
	_dead_since = _elapsed
	_once = &""
	var host := get_tree().get_first_node_in_group(Fx.GROUP)
	if host == null:
		host = get_parent().get_parent()
	if host != null:
		reparent(host)
	_refresh()
	var dying := float(_body.hframes) / ONCE_FPS
	var tween := create_tween()
	tween.tween_interval(dying + CORPSE_STAY)
	tween.tween_property(self, "modulate:a", 0.0, CORPSE_FADE)
	tween.tween_callback(queue_free)


## 现在显示的动作名（测试用）。
func clip() -> StringName:
	if _dead:
		return &"death"
	if _once != &"":
		return _once
	if _prone:
		return &"prone"
	if _aiming_diagonally():
		return _attack_clip()
	return &"walk" if _motion == Motion.WALK else &"idle"


func _attack_clip() -> StringName:
	return ATTACK_BY_AIM.get(Vector2(absf(signf(_aim.x)), signf(_aim.y)), &"attack_level")


func _aiming_diagonally() -> bool:
	return _aim.x != 0.0 and _aim.y != 0.0


func _play_once(name: StringName) -> void:
	if _dead:
		return
	_once = name
	_once_since = _elapsed
	_refresh()


func _refresh() -> void:
	if _body == null:
		return # _ready 之前玩法就可能调过来，等 _ready 里统一刷一次
	var file := "%s/%s_%s.png" % [art_dir, clip(), &"r" if _facing >= 0 else &"l"]
	var texture: Texture2D = load(file)
	if texture == null:
		push_warning("敌人贴图缺失：%s" % file)
		return
	_body.texture = texture
	_body.hframes = maxi(1, texture.get_width() / frame_size.x)
	_advance()


func _advance() -> void:
	if _body == null or _body.texture == null:
		return
	var last := _body.hframes - 1
	if _dead:
		_body.frame = mini(int((_elapsed - _dead_since) * ONCE_FPS), last)
	elif _once != &"":
		_body.frame = mini(int((_elapsed - _once_since) * ONCE_FPS), last)
	elif _prone or _aiming_diagonally():
		_body.frame = 0 # 趴着 / 斜着举枪：停在第一帧，开火时才整组播
	else:
		var fps: float = LOOP_FPS.get(clip(), 0.0)
		_body.frame = int(_elapsed * fps) % _body.hframes if fps > 0.0 else 0
