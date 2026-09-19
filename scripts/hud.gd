extends CanvasLayer
## 临时 HUD：左上角用小方块显示血量、下面一条体力条、再下面一个色块表示当前武器、一排金色小方块表示终极武器剩余次数，死亡时显示提示。完整 HUD 留到第 5 步。

const PIP_SIZE := Vector2(6, 6)
const PIP_FULL := Color(0.9, 0.25, 0.3)
const PIP_EMPTY := Color(0.25, 0.2, 0.25)
const STAMINA_READY := Color(0.45, 0.85, 0.4)
## 体力低于能重新起跑的门槛时变色，提示玩家现在跑不动。
const STAMINA_TIRED := Color(0.85, 0.5, 0.25)

var _pips: Array[ColorRect] = []
var _ultimate_pips: Array[ColorRect] = []
var _player: Player

@onready var _pip_row: HBoxContainer = $PipRow
@onready var _message: Label = $Message
@onready var _stamina_bar: ColorRect = $StaminaBar
@onready var _stamina_fill: ColorRect = $StaminaBar/Fill
@onready var _weapon_icon: ColorRect = $WeaponIcon
@onready var _ultimate_row: HBoxContainer = $UltimateRow


func _ready() -> void:
	_message.hide()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	_player = player
	player.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.weapon_switched.connect(_on_weapon_switched)
	player.ultimate_ammo_changed.connect(_on_ultimate_changed)
	player.died.connect(_on_player_died)
	# 直接读当前值，不依赖 Player._ready 里那次 emit 的先后顺序。
	_on_health_changed(player.health, player.max_health)
	_on_stamina_changed(player.stamina, player.max_stamina)
	_on_weapon_switched(player.current_weapon, player.current_slot().weapon)
	if player.ultimate_weapon != null:
		_on_ultimate_changed(player.ultimate_ammo(), player.ultimate_weapon.max_ammo)


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


func _on_weapon_switched(_index: int, weapon: Weapon) -> void:
	_weapon_icon.color = weapon.hud_color


## 剩余的用武器自己的颜色，用掉的变暗。
func _on_ultimate_changed(ammo: int, max_ammo: int) -> void:
	while _ultimate_pips.size() < max_ammo:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(4, 4)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ultimate_row.add_child(pip)
		_ultimate_pips.append(pip)
	var full: Color = _player.ultimate_weapon.hud_color
	for i in _ultimate_pips.size():
		_ultimate_pips[i].color = full if i < ammo else full.darkened(0.75)


func _on_player_died() -> void:
	_message.show()
