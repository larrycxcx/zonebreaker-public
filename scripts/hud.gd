extends CanvasLayer
## 临时 HUD：左上角用小方块显示血量、下面一条体力条，死亡时显示提示。完整 HUD 留到第 5 步。

const PIP_SIZE := Vector2(6, 6)
const PIP_FULL := Color(0.9, 0.25, 0.3)
const PIP_EMPTY := Color(0.25, 0.2, 0.25)
const STAMINA_READY := Color(0.45, 0.85, 0.4)
## 体力低于能重新起跑的门槛时变色，提示玩家现在跑不动。
const STAMINA_TIRED := Color(0.85, 0.5, 0.25)

var _pips: Array[ColorRect] = []
var _player: Player

@onready var _pip_row: HBoxContainer = $PipRow
@onready var _message: Label = $Message
@onready var _stamina_bar: ColorRect = $StaminaBar
@onready var _stamina_fill: ColorRect = $StaminaBar/Fill


func _ready() -> void:
	_message.hide()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	_player = player
	player.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.died.connect(_on_player_died)
	# 直接读当前值，不依赖 Player._ready 里那次 emit 的先后顺序。
	_on_health_changed(player.health, player.max_health)
	_on_stamina_changed(player.stamina, player.max_stamina)


func _on_health_changed(health: int, max_health: int) -> void:
	while _pips.size() < max_health:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
		_pips.append(pip)
	for i in _pips.size():
		_pips[i].color = PIP_FULL if i < health else PIP_EMPTY


func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	var ratio := stamina / max_stamina if max_stamina > 0.0 else 0.0
	_stamina_fill.size.x = roundf(_stamina_bar.size.x * ratio)
	_stamina_fill.color = STAMINA_TIRED if _player.is_exhausted() else STAMINA_READY


func _on_player_died() -> void:
	_message.show()
