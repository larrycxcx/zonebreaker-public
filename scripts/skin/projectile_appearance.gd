class_name ProjectileAppearance
extends Appearance
## 精灵图版的发射物外观（子弹、手雷）：一个 Sprite2D，按飞行方向挑一张预先画好的贴图。
##
## 贴图由 `tools/projectile_build.py` 生成：子弹每种 8 张（right / left / up / down / up_right / ...），
## 手雷是圆的只有一张（`still` 填它的名字）。像素图不能在运行时转 45°（会糊），所以 8 个方向都是现成的。
## 子弹本体会按飞行方向整个转过去——那是判定（碰撞体是横着的细条），外观不能跟着转，
## 所以这里把自己的转角抵消掉，只靠换贴图表示方向。和角色外观一样纯显示：没有碰撞，换不换都不影响规则。

## 飞行方向（按 8 个方向取整）→ 贴图名。
const NAMES := {
	Vector2i(1, 0): &"right", Vector2i(-1, 0): &"left", Vector2i(0, -1): &"up", Vector2i(0, 1): &"down",
	Vector2i(1, -1): &"up_right", Vector2i(-1, -1): &"up_left", Vector2i(1, 1): &"down_right", Vector2i(-1, 1): &"down_left",
}

## 贴图放在哪个目录下。
@export_dir var art_dir := ""
## 不分方向的（手雷、圆弹）：贴图名；留空就按飞行方向挑。
@export var still := &""
## 这张贴图是一排几帧、每秒播几帧（手雷在空中翻滚）；1 帧就是静止的。
@export var frames := 1
@export var fps := 0.0

var _elapsed := 0.0

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	# 不调 super()：基类那套按位置镜像子节点的翻转法是给占位方块用的。
	_refresh()


func _process(delta: float) -> void:
	if frames <= 1 or fps <= 0.0:
		return
	_elapsed += delta
	_sprite.frame = int(_elapsed * fps) % frames


func aim(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_aim = direction
	_refresh()


## 现在用的贴图名（测试用）。
func texture_name() -> StringName:
	if still != &"":
		return still
	# 8 个方向之一：按角度取整到 45° 的倍数，免得 (0.7, 0.7) 这种被四舍五入成 (1, 1) 以外的东西
	var step := roundi(_aim.angle() / (PI / 4.0))
	var snapped := Vector2.RIGHT.rotated(step * PI / 4.0)
	return NAMES[Vector2i(roundi(snapped.x), roundi(snapped.y))]


func _refresh() -> void:
	if _sprite == null:
		return # _ready 之前可能被调过来，等 _ready 里统一刷一次
	if is_inside_tree():
		global_rotation = 0.0
	var file := "%s/%s.png" % [art_dir, texture_name()]
	var texture: Texture2D = load(file)
	if texture == null:
		push_warning("发射物贴图缺失：%s" % file)
		return
	_sprite.texture = texture
	_sprite.hframes = maxi(1, frames)
