class_name BossPodAppearance
extends BossSkullAppearance
## 第五关 Boss「生化舱」的外观：激光、蓄力、一次性动作（三门炮各一组）都是骷髅头那一套，
## 多一个**缩壳**——玩法说缩着就一直循环圆壳那几帧（`shell`），持续多久是玩法定的。
## 占位方块没有 `show_shell()`，默认皮肤下不画，规则一点不变。

var _shell := false


func show_shell(on: bool) -> void:
	if on == _shell:
		return
	_shell = on
	_refresh()


func is_shelled() -> bool:
	return _shell


func clip() -> StringName:
	if _shell and not _dead:
		return &"shell"
	return super()
