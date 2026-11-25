extends Node
## Settings for this session (the autoload singleton Session): how many players. The main menu sets it later, and the level spawns players from it.
##
## Input: player 1's action names are `move_left`, `shoot`..., player 2's are `p2_move_left`, `p2_shoot`... (see `Player.act()`).
## Pads are split: one pad per seat. **Which pad is which player is decided by the press on the title screen** (`claim_pads()`),
## not hard-coded as device 0 / 1 — Godot gives device numbers in plug-in order, and the player's "pad 1"
## may well be device 1 (an earlier slot held by a ghost device that was not cleanly unplugged is common).
## Keyboard: the arrow keys are player 1's alternative keys when playing alone; **in co-op they go to player 2** (player 2 moves / aims with the arrows,
## `.` jumps, `/` fires, `,` goes prone, `L` runs, `;` switches weapons, `'` fires the ultimate), and they go back to player 1 when returning to one player.

const MAX_PLAYERS := 2
## Keys taken from player 1's actions and given to player 2 in co-op.
const SHARED_KEYS: Array[int] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

var player_count := 1

## Device number of **the last pad that pressed something**, -1 = none yet (or the last press was on the keyboard).
## The title screen uses it to decide "who is player 1".
var last_pad := -1

## Keys lent to player 2 (action → event), returned when going back to one player.
var _lent := {}
## Which pad each seat is bound to right now. By default as configured in `project.godot` (seat N ↔ device N).
var _pads: Array[int] = [0, 1]
## **Actions deliberately bound to more than one pad** (action name → the pad event used as the template):
## `pause` is one — both players can pause, so it has the Start button of two pads.
## Rebinding per seat would squash it to one pad (after claiming only one player could pause),
## so after every rebind `_spread_shared()` spreads it over every pad again.
## **This must be worked out before any rebinding**, or afterwards there is no way to tell it used to be shared.
var _shared: Dictionary = {}


func _ready() -> void:
	_find_shared_actions()
	set_player_count(int(ProjectSettings.get_setting("game/player_count", 1)))


## Remember which pad pressed last. A stick only counts once pushed past the dead zone — springing back on release also sends events.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		last_pad = event.device
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			last_pad = event.device


# ---------------------------------------------------------------- Which pad is which player

## **The pad that made this press is player 1**, the other connected ones follow in order.
## Called once on the title screen (after choosing how many players). If `first` is -1 (the press came from the keyboard), nothing changes.
##
## Why this is needed: Godot hands out device numbers **in plug-in order**, which has nothing to do with the player's idea of "pad 1".
## With a hard-coded "seat 0 ↔ device 0", if the pad in the player's hands is device 1,
## everything works on the title screen (anyone's press counts), but the screen saying PLAYER 1 no longer responds,
## while the other pad does — exactly what the 2026-09 playtest reported.
func claim_pads(first: int) -> void:
	if first < 0:
		return
	# **Two seats cannot share one pad**: if the pad claimed belonged to another seat, swap them.
	# Without the swap, with only one pad plugged in and two players chosen, both seats would listen to the same pad — one person moves and both characters move.
	var was: int = _pads[0]
	for seat in range(1, MAX_PLAYERS):
		if _pads[seat] == first:
			_bind_pad(seat, was)
	_bind_pad(0, first)
	var others: Array = Input.get_connected_joypads().filter(
		func(device: int) -> bool: return device != first)
	for seat in range(1, MAX_PLAYERS):
		if others.size() >= seat:
			_bind_pad(seat, others[seat - 1])
	_spread_shared()


## Which pad this seat is bound to right now (for tests).
func pad_of(seat: int) -> int:
	return _pads[seat] if seat >= 0 and seat < _pads.size() else -1


## Back to how `project.godot` configures it (seat N ↔ device N).
## **InputMap is global state**: every test has to restore it, or a claim made in one test leaks into the following ones.
func reset_pads() -> void:
	last_pad = -1
	for seat in MAX_PLAYERS:
		_bind_pad(seat, seat)
	_spread_shared()


## Point every **pad event** on this seat's actions at this pad. None of the keyboard events are touched.
func _bind_pad(seat: int, device: int) -> void:
	if device < 0:
		return
	_pads[seat] = device
	for action in InputMap.get_actions():
		var name := String(action)
		if name.begins_with("ui_"):
			continue
		if name.begins_with("p2_") != (seat == 1):
			continue
		for event in InputMap.action_get_events(action):
			if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
				continue
			# **Erase it, then add a fresh copy**: changing `device` on the copy you got back
			# does not update InputMap's internal per-device index.
			InputMap.action_erase_event(action, event)
			var moved := event.duplicate()
			moved.device = device
			InputMap.action_add_event(action, moved)


## Which actions are bound to more than one pad to begin with. **Worked out only once, at start-up**.
func _find_shared_actions() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var devices := {}
		var sample: InputEvent = null
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				devices[event.device] = true
				if sample == null:
					sample = event
		if devices.size() > 1:
			_shared[action] = sample


## Spread the shared actions over **the pad each seat has now**, one copy per pad.
func _spread_shared() -> void:
	for action: StringName in _shared:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
		for device in _pads:
			var copy: InputEvent = (_shared[action] as InputEvent).duplicate()
			copy.device = device
			InputMap.action_add_event(action, copy)


func set_player_count(count: int) -> void:
	player_count = clampi(count, 1, MAX_PLAYERS)
	if player_count >= 2:
		_lend_shared_keys()
	else:
		_take_back_shared_keys()


# ---------------------------------------------------------------- UI input

## Was this action of this seat **just pressed this frame**? All UI input (`MenuList`, `ShopColumn`) goes through this.
##
## **When playing alone anyone's press counts**: splitting by device is so that two players each use their own pad; alone there is nothing to split.
## Without this, the same keys work on the first few menu pages and suddenly stop at character setup and the shop (the first pages that filter input by player)
## — with the pad in the second slot (an earlier slot held by a ghost device that was not cleanly unplugged is common) whole pages go dead,
## and ↑ on the keyboard turns from "move up" into "confirm" (alone, ↑ is player 1's jump and at the same time player 2's "up").
func just_pressed(action: StringName, seat: int) -> bool:
	if seat >= 0 and player_count >= 2:
		return _pressed(action_for(action, seat))
	for index in MAX_PLAYERS:
		if _pressed(action_for(action, index)):
			return true
	return false


## The name of this action for a given player (player 1 has no prefix).
func action_for(action: StringName, seat: int) -> StringName:
	return action if seat <= 0 else StringName("p%d_%s" % [seat + 1, action])


## **An action that does not exist counts as not pressed**: asking the engine about a missing action is an error, reported every frame.
## Not every player has every UI action configured (even less so if a third seat is ever added).
func _pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _lend_shared_keys() -> void:
	if not _lent.is_empty():
		return
	for action in InputMap.get_actions():
		var name := String(action)
		if name.begins_with("ui_") or name.begins_with("p2_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and SHARED_KEYS.has((event as InputEventKey).physical_keycode):
				InputMap.action_erase_event(action, event)
				if not _lent.has(action):
					_lent[action] = []
				_lent[action].append(event)


func _take_back_shared_keys() -> void:
	for action: StringName in _lent:
		for event: InputEvent in _lent[action]:
			InputMap.action_add_event(action, event)
	_lent.clear()
