extends CanvasLayer
## 临时 HUD：左上角用小方块显示血量，死亡时显示提示。完整 HUD 留到第 5 步。

const PIP_SIZE := Vector2(6, 6)
const PIP_FULL := Color(0.9, 0.25, 0.3)
const PIP_EMPTY := Color(0.25, 0.2, 0.25)

var _pips: Array[ColorRect] = []

@onready var _pip_row: HBoxContainer = $PipRow
@onready var _message: Label = $Message


func _ready() -> void:
	_message.hide()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	# 直接读当前值，不依赖 Player._ready 里那次 emit 的先后顺序。
	_on_health_changed(player.health, player.max_health)


func _on_health_changed(health: int, max_health: int) -> void:
	while _pips.size() < max_health:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
		_pips.append(pip)
	for i in _pips.size():
		_pips[i].color = PIP_FULL if i < health else PIP_EMPTY


func _on_player_died() -> void:
	_message.show()
