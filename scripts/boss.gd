class_name Boss
extends Enemy
## Boss 敌人的基类。关卡里的其它敌人（A/B/C/D/E/炮台）都是普通敌人，直接继承 Enemy。
##
## 和普通敌人的区别：
## - **出场**：进入屏幕之前处于待机状态（只受重力，不行动）；身体**任何一部分**第一次进入屏幕时「出场」——
##   （按中心点算的话，宽的 Boss 中心还在屏幕外时已经露出一大截、玩家打得到它，它却还在待机。
##   待机时被打中也立刻出场，免得还有别的办法在它醒来之前白打。）
##   报告 appear_event（特殊音效），通过 GameEvents.boss_appeared 通知 HUD 在右上角显示头像和血条。只出场一次。
## - **终极武器**：定格和清子弹对 Boss 一样有效（暂停整棵树、Boss 的子弹也在 enemy_bullets 组里），
##   但不会被直接消灭，而是受到 ultimate_damage() 点伤害 = 最大血量 × ultimate_damage_ratio（血量不够时照样会被打死）。
## - 血量变化发 health_changed，HUD 的血条接这个。
##
## 具体的攻击方式写在子类的 _boss_process() 里，每个 Boss 各不相同。

## 血量变化（包括出场那一刻），HUD 血条接这个。
signal health_changed(health: int, max_health: int)

## 名字（以后 HUD、过场用）。
@export var display_name := "BOSS"
## HUD 右上角的头像（占位美术放在 skins/default/portraits/）。素材包的外观带了头像就用外观的，见 hud_portrait()。
@export var portrait: Texture2D
## 被终极武器打中时受到的伤害占最大血量的比例（0.25 = 四分之一，4 次打死）。每个 Boss 可以不同。
@export_range(0.0, 1.0) var ultimate_damage_ratio := 0.25
## 出场时报告的事件名（素材包按它找声音）。
@export var appear_event := &"boss_appear"

var has_appeared := false


func _physics_process(delta: float) -> void:
	if not has_appeared:
		_apply_gravity(delta)
		move_and_slide()
		if is_partly_on_screen():
			appear()
		return
	_boss_process(delta)


## 子类在这里写行为（出场之后每个物理帧调用）。
func _boss_process(_delta: float) -> void:
	pass


## 出场：只会发生一次。一般由「进入屏幕」触发，脚本关卡也可以直接调用。
func appear() -> void:
	if has_appeared:
		return
	has_appeared = true
	GameEvents.report(appear_event, self)
	GameEvents.boss_appeared.emit(self)
	health_changed.emit(health, max_health)


func take_damage(amount: int, source_position := Vector2.INF) -> void:
	if health <= 0:
		return
	appear()
	super.take_damage(amount, source_position)
	health_changed.emit(maxi(health, 0), max_health)


## 终极武器一次造成的伤害（向上取整，至少 1）。
func ultimate_damage() -> int:
	return maxi(1, ceili(max_health * ultimate_damage_ratio))


## 终极武器对 Boss 只造成伤害，不直接消灭。
func hit_by_ultimate() -> void:
	take_damage(ultimate_damage())


## HUD 上显示的头像：外观（素材包）自己带了头像就用它，头像跟着皮肤换；否则用场景里配的占位头像。
func hud_portrait() -> Texture2D:
	var skinned: Variant = _visual.get(&"portrait") if _visual != null else null
	return skinned if skinned is Texture2D else portrait
