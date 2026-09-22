class_name Bullet
extends Area2D
## 直线飞行的子弹。撞到任何碰撞体就消失，命中目标时造成伤害。
## 打谁由场景里的 collision_mask 决定（玩家子弹打 world+enemy，敌人子弹打 world+player）。
## 单向平台不挡子弹：玩家能从下面穿过去，子弹也一样，否则站在平台上的敌人从下面永远打不到。

@export var speed := 520.0
@export var lifetime := 1.2
@export var damage := 1
## 素材包里用哪一项画它（`SkinPack.APPEARANCE_KEYS`，和角色同一套）。只管长什么样，和规则无关。
@export var skin_key := &""

var direction := Vector2.RIGHT

var _age := 0.0


## 武器槽发射时调用（在加入场景树之前）。
func launch(direction_: Vector2) -> void:
	direction = direction_


## 按武器和攻击力放大伤害（武器槽在发射时调，加入场景树之前）。
func scale_damage(factor: float) -> void:
	damage = maxi(1, roundi(damage * factor))


func _ready() -> void:
	# 外形是横着的细条，按飞行方向转过去（向上打时变成竖条）。
	# direction 在 add_child 之前就设好了，所以这里读到的是最终值。
	rotation = direction.angle()
	# 占位的细条跟着本体一起转；素材包的贴图按方向挑一张现成的（见 ProjectileAppearance）
	var visual := Skins.build_appearance(self, skin_key)
	if visual != null:
		visual.aim(direction)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Platform and (body as Platform).one_way:
		return
	if body.has_method("take_damage"):
		# 打中角色的声音由被打的一方报告（enemy_hit / player_hurt 等）。
		body.take_damage(damage, global_position)
	else:
		GameEvents.report(&"bullet_impact", self)
	queue_free()
