class_name Boss
extends Enemy
## Boss 敌人的基类。关卡里的其它敌人（A/B/C/D/E/炮台）都是普通敌人，直接继承 Enemy。
##
## 和普通敌人的区别：
## - **出场**：进入屏幕之前处于待机状态（只受重力，不行动）；第一次进入屏幕时「出场」——
##   报告 appear_event（特殊音效），通过 GameEvents.boss_appeared 通知 HUD 在右上角显示头像和血条。只出场一次。
## - **终极武器**：定格和清子弹对 Boss 一样有效（暂停整棵树、Boss 的子弹也在 enemy_bullets 组里），
##   但不会被直接消灭，而是受到 ultimate_damage 点伤害（血量不够时照样会被打死）。
## - 血量变化发 health_changed，HUD 的血条接这个。
##
## 具体的攻击方式写在子类的 _boss_process() 里，每个 Boss 各不相同。

## 血量变化（包括出场那一刻），HUD 血条接这个。
signal health_changed(health: int, max_health: int)

## 名字（以后 HUD、过场用）。
@export var display_name := "BOSS"
## HUD 右上角的头像（占位美术放在 skins/default/portraits/）。
@export var portrait: Texture2D
## 被终极武器打中时受到的伤害。每个 Boss 可以不同。
@export var ultimate_damage := 10
## 出场时报告的事件名（素材包按它找声音）。
@export var appear_event := &"boss_appear"

var has_appeared := false


func _physics_process(delta: float) -> void:
	if not has_appeared:
		_apply_gravity(delta)
		move_and_slide()
		if is_on_screen():
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
	super.take_damage(amount, source_position)
	health_changed.emit(maxi(health, 0), max_health)


## 终极武器对 Boss 只造成伤害，不直接消灭。
func hit_by_ultimate() -> void:
	take_damage(ultimate_damage)
