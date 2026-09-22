class_name SpriteEffect
extends Node2D
## 精灵图版的短命特效（枪口闪光、命中火花、撞墙火花）：播一遍序列帧后自己消失。纯显示，没有碰撞。
##
## 有方向的（枪口闪光、撞墙火花）：`Fx` 调 `point(方向)`，从 8 个方向里挑一张现成画好的——像素图不能在运行时转 45°。
## 贴图由 `tools/fx_build.py` 生成，喷出点在每帧正中，所以特效的原点就是枪口 / 命中点。
## 不分方向的（打中角色）：`textures` 里只放一张 `&"still"`。

## 贴图：方向名（right / up_left / …，和 ProjectileAppearance 一样）→ 一排正方形帧；不分方向的只放 `still`。
@export var textures: Dictionary[StringName, Texture2D] = {}
## 每帧边长、每秒几帧。
@export var frame_size := 32
@export var fps := 30.0
## 素材是白色剪影时用它染色（乘上去）。
@export var tint := Color.WHITE

var _direction := Vector2.RIGHT
var _elapsed := 0.0

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	modulate = tint
	_refresh()


## 朝哪个方向喷（Fx 生成之后调）。
func point(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_direction = direction
	_refresh()


## 现在用的贴图名（测试用）。
func texture_name() -> StringName:
	if textures.has(&"still"):
		return &"still"
	return ProjectileAppearance.direction_name(_direction)


func _process(delta: float) -> void:
	_elapsed += delta
	var frame := int(_elapsed * fps)
	if frame >= _sprite.hframes:
		queue_free()
		return
	_sprite.frame = frame


func _refresh() -> void:
	if _sprite == null:
		return
	var texture: Texture2D = textures.get(texture_name())
	if texture == null:
		push_warning("特效贴图缺失：%s" % texture_name())
		return
	_sprite.texture = texture
	_sprite.hframes = maxi(1, texture.get_width() / frame_size)
	_sprite.frame = mini(int(_elapsed * fps), _sprite.hframes - 1)
