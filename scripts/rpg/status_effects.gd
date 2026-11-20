class_name StatusEffects
extends RefCounted
## 一个角色身上正挂着的异常状态：计时、按间隔扣血、到时间解除。玩家和敌人各有一个（`statuses`），
## 由角色每个物理帧调 `tick(delta)`，扣血通过 `on_damage` 回调交给角色自己（玩家、敌人扣血的方式不一样）。
##
## 同一种状态再中一次：**刷新持续时间**（取剩余和新时间里长的那个），不叠加伤害。
## 抗性由角色在挂之前给（`apply(effect, resist)`）：持续时间 × (1 - 抗性)，1 = 免疫、根本挂不上。

## 某个状态挂上 / 解除（外观、HUD 以后接这个）。
signal changed(id: StringName, active: bool)

## 每跳扣血时调它：func(amount: int) -> void。
var on_damage: Callable

## id → {effect, left, next_tick}
var _active := {}
## 计时的容差：帧时长累加有浮点误差，「1 秒、每 0.25 秒一跳」的最后一跳正好落在结束那一刻，不留余量就会漏掉。
const EPSILON := 0.0001


## 挂上一个状态，返回是否挂上了（完全免疫、持续时间为 0 就不挂）。
func apply(effect: StatusEffect, resist := 0.0) -> bool:
	if effect == null or effect.id == &"":
		return false
	var duration := effect.duration * (1.0 - clampf(resist, 0.0, 1.0))
	if duration <= 0.0:
		return false
	var fresh := not _active.has(effect.id)
	if fresh:
		_active[effect.id] = {"effect": effect, "left": duration, "next_tick": effect.tick_interval}
		changed.emit(effect.id, true)
	else:
		_active[effect.id]["left"] = maxf(_active[effect.id]["left"], duration)
	return true


func tick(delta: float) -> void:
	for id: StringName in _active.keys():
		var entry: Dictionary = _active[id]
		var effect: StatusEffect = entry["effect"]
		var left: float = entry["left"] - delta
		if effect.tick_damage > 0 and effect.tick_interval > 0.0:
			var next: float = entry["next_tick"] - delta
			while next <= EPSILON and left > -effect.tick_interval:
				if on_damage.is_valid():
					on_damage.call(effect.tick_damage)
				next += effect.tick_interval
			entry["next_tick"] = next
		entry["left"] = left
		if left <= EPSILON and _active.has(id):
			_active.erase(id)
			changed.emit(id, false)


## 现在挂着这个状态吗。
func has(id: StringName) -> bool:
	return _active.has(id)


## 这个状态还剩多久（没挂返回 0）。
func time_left(id: StringName) -> float:
	return _active[id]["left"] if _active.has(id) else 0.0


## 所有状态合起来：移动速度乘多少、能不能行动。
func move_scale() -> float:
	var scale := 1.0
	for entry: Dictionary in _active.values():
		scale *= (entry["effect"] as StatusEffect).move_scale
	return scale


func can_act() -> bool:
	for entry: Dictionary in _active.values():
		if not (entry["effect"] as StatusEffect).can_act:
			return false
	return true


## 全部解除。**先清空再发信号**：听信号的（HUD 那行字）收到时会回头查 `has()`，
## 反过来的话它查到的状态还挂着，那行 POISON 就一直不消失（写中毒的测试时撞到的）。
func clear() -> void:
	var ids := _active.keys()
	_active.clear()
	for id: StringName in ids:
		changed.emit(id, false)
