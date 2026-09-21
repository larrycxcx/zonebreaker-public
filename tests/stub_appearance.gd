extends Appearance
## 测试用的替身外观：什么都不画，只记下玩法调了哪些接口。
##
## 用它 `set_script()` 换掉真正的外观之后，游戏必须照常运行、判定一点都不变——
## 这就是「玩法不依赖外观」最直接的证据。换皮肤要做的事，和这里做的是同一件事。

var calls: Array[String] = []


func face(_facing: int) -> void:
	calls.append("face")


func aim(_direction: Vector2) -> void:
	calls.append("aim")


func motion(_state: Appearance.Motion) -> void:
	calls.append("motion")


func pose(_height_ratio: float, _lowered: float) -> void:
	calls.append("pose")


func kick(_offset: Vector2) -> void:
	calls.append("kick")


func flash_hit() -> void:
	calls.append("flash_hit")


func blink(_alpha: float) -> void:
	calls.append("blink")


func show_dead() -> void:
	calls.append("show_dead")
