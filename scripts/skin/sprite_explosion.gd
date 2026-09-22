class_name SpriteExplosion
extends Node2D
## 精灵图版的爆炸特效：按爆炸半径挑一档大小最接近的序列帧，1:1 播一遍后自己消失（像素图不缩放）。
## 和占位的 explosion.gd 一样只管显示，伤害由 Grenade 算；`Fx` 生成它之后才设 `radius`，所以半径改了就重新挑图。

## 各档贴图：帧边长 → 一排正方形帧（tools/fx_build.py 生成）。
@export var sizes: Dictionary[int, Texture2D] = {}
@export var fps := 16.0
@export var radius := 56.0:
	set(value):
		radius = value
		_pick()

var _elapsed := 0.0

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_pick()


func _process(delta: float) -> void:
	_elapsed += delta
	var frame := int(_elapsed * fps)
	if frame >= _sprite.hframes:
		queue_free()
		return
	_sprite.frame = frame


## 现在用的是哪一档（帧边长，测试读）。
func frame_size() -> int:
	return _best_size()


## 离爆炸直径最近的那一档。
func _best_size() -> int:
	var best := 0
	for size: int in sizes:
		if best == 0 or absf(size - radius * 2.0) < absf(best - radius * 2.0):
			best = size
	return best


func _pick() -> void:
	if _sprite == null:
		return # _ready 之前被设了半径，等 _ready 里统一挑
	var size := _best_size()
	if size == 0:
		return
	_sprite.texture = sizes[size]
	_sprite.hframes = maxi(1, _sprite.texture.get_width() / size)
	_sprite.frame = mini(int(_elapsed * fps), _sprite.hframes - 1)
