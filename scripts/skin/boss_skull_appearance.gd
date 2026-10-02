class_name BossSkullAppearance
extends EnemySpriteAppearance
## 地下室 Boss「骷髅头」的外观：骷髅走基类那套贴图，另外**按玩法给的长度画一道激光**。
##
## 素材的出光帧里激光只伸出去四十几像素，而玩法要它射到对面的墙为止，
## 所以把激光拆成「一列」（`beam_thick` / `beam_thin`）横着平铺，长度由玩法说了算。
## 和机械臂（`BossArmAppearance`）同一个做法：**玩法只调 `show_beam()` 和 `play()`**，
## 占位方块那套没有这两个方法，默认皮肤下就是不画——规则一点不变。
##
## 蓄力和出光是**循环的**（持续多久是玩法定的，不是播一遍就完）：蓄力循环攻击的前两帧（`charge`），
## 出光循环后两帧（`beam`），激光一粗一细地闪。

@export var beam_thick: Texture2D
@export var beam_thin: Texture2D
## 激光从骨手哪儿出来（相对身体原点，朝右时）。和 `BossSkull.BEAM_ORIGIN` 是同一个点。
@export var beam_origin_x := 20.0
## 蓄力、出光循环多快。
@export var beam_fps := 10.0

## 0 = 没在打激光，1 = 蓄力，2 = 出光。
var _beam_state := 0
var _beam_length := 0.0
## 激光相对身体原点的高度（玩法锁定的那一条）。
var _beam_dy := 16.0


## 玩法每帧告诉它：现在在不在打激光、射多长、在哪个高度。
func show_beam(state: int, length: float, dy: float) -> void:
	if state == _beam_state and is_equal_approx(length, _beam_length) and is_equal_approx(dy, _beam_dy):
		return
	var changed := state != _beam_state
	_beam_state = state
	_beam_length = length
	_beam_dy = dy
	if changed:
		_refresh()
	queue_redraw()


## 打骨弹时基类每发都会调这个「播一遍开火动作」——**骷髅头没有那一组**（`attack_level`），
## 照基类去找就是每发一条「Resource file not found」（截图看出来的，第二关 2-C 当年同一个毛病）。
## 打骨弹的时候玩法已经让它在循环蓄力那两帧（骨手发光），所以这里什么都不用播。
## 也不能拿出光那组顶上：那组画面里带着一截水平的激光，往下打骨弹时对不上。
func fire() -> void:
	pass


## 同理：斜着打一发骨弹之后，基类会当它「斜着举枪」、去显示开火那一组（这包没有）。
## 骷髅头没有瞄准的姿势，瞄哪儿都是同一张脸。
func aim(_direction: Vector2) -> void:
	pass


## 播一遍某个一次性动作（召唤、嘲讽）。
func play(clip_name: StringName) -> void:
	_play_once(clip_name)


func clip() -> StringName:
	if _dead or _once != &"":
		return super()
	if _beam_state == 1:
		return &"charge"
	if _beam_state == 2:
		return &"beam"
	return super()


func _advance() -> void:
	if _beam_state != 0 and not _dead and _once == &"" and _body != null and _body.texture != null:
		_body.frame = int(_elapsed * beam_fps) % _body.hframes
		queue_redraw()
		return
	super()


func _draw() -> void:
	if _beam_state != 2 or _beam_length <= 0.0 or _dead:
		return
	# 一粗一细地闪，和素材出光那两帧一个节奏
	var thick := int(_elapsed * beam_fps) % 2 == 0
	var tile := beam_thick if thick or beam_thin == null else beam_thin
	if tile == null:
		return
	var h := float(tile.get_height())
	var x := beam_origin_x * _facing
	var rect := Rect2(x if _facing >= 0 else x - _beam_length, _beam_dy - h / 2.0, _beam_length, h)
	draw_texture_rect(tile, rect, true)
