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
##   斜着瞄准 → 有 idle_up / idle_down 就循环播它（炮台：斜着的炮管照样上下浮动），
##              没有就停在 attack_up / attack_down 第 1 帧（巡逻兵举着枪等开火）；E 一直朝正下方，那不算「斜着」
## 受伤同理：斜着瞄准时有 hurt_up / hurt_down 就用它，免得挨一下炮管就跳回水平。
##   冲（D 追击）→ run；在空中 → air；没有这两组就退回 walk
##   在走 → walk；站着 → idle

## 地面敌人每帧的大小和锚点（帧里对应敌人身体原点的那个像素），必须和 tools/enemy_build.py 一致。
## 比玩家的帧宽：倒地时人扑在身前，56 宽装不下。飞的 E 不一样，在它自己的场景里改 frame_size / anchor。
const FRAME_W := 80
const FRAME_H := 56
const ANCHOR_X := 40
const ANCHOR_Y := 40

## 循环动作的速度（帧/秒）。
const LOOP_FPS := {&"idle": 6.0, &"idle_up": 6.0, &"idle_down": 6.0, &"walk": 10.0, &"run": 12.0}
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
@export_dir var art_dir := "res://skins/cyberpunk/enemies/1_a"
## Boss 在 HUD 上的头像（换皮肤时头像跟着换）；普通敌人留空。
@export var portrait: Texture2D
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
## 播完停在最后一帧（`play_once(…, true)`）：第五关科学家变身，最后一帧已经是变异体的样子，停在那儿等换人。
var _hold := false
## 埋在地下：停在 `emerge` 那组的第一帧（只有一块履带）。
var _buried := false
var _dead_since := 0.0
## 这套贴图有没有某个动作（按名字缓存，免得每帧问文件系统）。
var _has := {}


func _ready() -> void:
	# 不调 super()：基类那套按位置镜像子节点的翻转法是给占位方块用的，这里靠换贴图翻转。
	_body.centered = true
	_body.offset = Vector2(frame_size) / 2.0 - Vector2(anchor)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _once != &"" and not _dead and not _hold and _body.texture != null \
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


## 开一枪：按现在的姿势播一遍开火动作（趴着就是趴着开火那组，边走边打有 attack_walk 就用它）。
func fire() -> void:
	if _prone:
		_play_once(&"prone")
	elif _motion == Motion.WALK and _exists(&"attack_walk"):
		_play_once(&"attack_walk")
	else:
		_play_once(_attack_clip())


## 挨了一下：播一遍受伤（素材的第 2 帧是整个人闪红）。
func flash_hit() -> void:
	_play_once(_aimed(&"hurt"))


## 没有倒地动画时原地炸的那一团多大（半径）。
const DEATH_BLAST := 40.0


## 死了：本体马上会被删掉，所以外观把自己挪到特效层下面，播完倒地、躺一会儿、淡出后自己消失。
## 特效层不在（比如测试把它删了）就挂到敌人的父节点下，效果一样。
func show_dead() -> void:
	if _dead:
		return
	_dead = true
	_dead_since = _elapsed
	_once = &""
	var host := get_tree().get_first_node_in_group(Fx.GROUP)
	if not _exists(&"death"):
		# 没有倒地动画的（第五关的大型机甲）：**原地炸一团**就没了。不去加载不存在的贴图——
		# 那会每次刷一条「Resource file not found」（第二关 2-C 斜射踩过同一个坑）
		var boom_scene := Skins.effect(&"explosion", null)
		if boom_scene != null and host != null:
			var boom := boom_scene.instantiate() as Node2D
			host.add_child(boom)
			boom.global_position = global_position
			boom.set(&"radius", DEATH_BLAST)
		queue_free()
		return
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
	if _buried:
		return &"emerge"
	if _once != &"":
		return _once
	if _prone:
		return &"prone"
	if _aiming_diagonally():
		var idle := _aimed(&"idle")
		return idle if idle != &"idle" else _attack_clip()
	match _motion:
		Motion.WALK:
			return &"walk"
		Motion.RUN:
			return _first([&"run", &"walk"])
		Motion.JUMP, Motion.FALL:
			return _first([&"air", &"run", &"walk"])
	return &"idle"


## 这个瞄准方向的开火动作。**贴图里没有就退回水平那组**——
## 不是每套素材都画了斜射：赛博朋克那个巡逻兵自带水平 / 斜上 / 斜下三组，
## 工业区那套只有水平一组。没有这条兜底的话，2-C 一斜着瞄就去加载一张不存在的图，
## 刷一屏「Resource file not found」，画面上那一帧也没了。
func _attack_clip() -> StringName:
	var wanted: StringName = ATTACK_BY_AIM.get(
		Vector2(absf(signf(_aim.x)), signf(_aim.y)), &"attack_level")
	return _first([wanted, &"attack_level"])


func _aiming_diagonally() -> bool:
	return _aim.x != 0.0 and _aim.y != 0.0


## 这套贴图里有的第一个动作（最后一个当兜底，不查）。
func _first(names: Array[StringName]) -> StringName:
	for name in names.slice(0, -1):
		if _exists(name):
			return name
	return names[-1]


func _exists(name: StringName) -> bool:
	if not _has.has(name):
		_has[name] = ResourceLoader.exists("%s/%s_r.png" % [art_dir, name])
	return _has[name]


## 斜着瞄准时这个动作的斜向版本（`hurt` → `hurt_up`），贴图里没有就还是原来那个。
func _aimed(name: StringName) -> StringName:
	if not _aiming_diagonally():
		return name
	var variant := StringName("%s_%s" % [name, "up" if _aim.y < 0.0 else "down"])
	return variant if _exists(variant) else name


## 播一遍某个动作（玩法用：科学家变身）。`hold` = 播完停在最后一帧，不回待机。
## 这套贴图没有这个动作就什么都不做。
func play_once(name: StringName, hold := false) -> void:
	if not _exists(name):
		return
	_play_once(name)
	_hold = hold


func show_buried(buried: bool) -> void:
	_buried = buried
	_refresh()


## 钻出来：播一遍 `emerge`（履带滑开、机甲升上来），播完回待机。
func emerge() -> void:
	_buried = false
	play_once(&"emerge")


## 这个动作要播多久（秒）：一帧 `ONCE_FPS` 分之一秒。没有这个动作返回 0。
func once_length(name: StringName) -> float:
	if not _exists(name):
		return 0.0
	var texture: Texture2D = load("%s/%s_r.png" % [art_dir, name])
	return float(texture.get_width()) / float(frame_size.x) / ONCE_FPS


func _play_once(name: StringName) -> void:
	if _dead:
		return
	_hold = false
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
	elif _prone or (_aiming_diagonally() and clip() == _attack_clip()):
		_body.frame = 0 # 趴着 / 斜着举枪：停在第一帧，开火时才整组播
	else:
		var fps: float = LOOP_FPS.get(clip(), 0.0)
		_body.frame = int(_elapsed * fps) % _body.hframes if fps > 0.0 else 0
