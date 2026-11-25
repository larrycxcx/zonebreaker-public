extends Appearance
## A stand-in appearance for tests: draws nothing, only records which interface methods gameplay called.
##
## After swapping out the real look with `set_script()` the game has to run as usual with the hit checks completely unchanged —
## the most direct evidence that "gameplay does not depend on the look". Making a new skin is the same thing as what is done here.

var calls: Array[String] = []


func face(_facing: int) -> void:
	calls.append("face")


func aim(_direction: Vector2) -> void:
	calls.append("aim")


func fire() -> void:
	calls.append("fire")


func hold(_look: StringName) -> void:
	calls.append("hold")


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
