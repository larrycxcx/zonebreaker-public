extends Node
## Character roster and seats (the autoload singleton Progress): the save holds a roster of **characters**, and at the start each player picks one to sit in.
##
## **The identity is the character, not the seat**: a character can play in a different seat next time, but two seats cannot use the same character at once.
## What a progress record holds and how stats are worked out is all in `PlayerProgress`; this handles four things:
## the roster (create / delete / duplicate-name check), the seats (`of(index)` returns the character a player is using now), saving, and who gets each kill reward.
##
## The save is written to `save_path` whenever any character changes; in tests `persist = false`, so the player's real save is neither read nor written.
## **Old saves still load**: before co-op it was one progress record at the top level, after co-op two of them under `players`; both are migrated into roster characters.
##
## Kill rewards: listens to GameEvents' `enemy_death` and pays the `xp_reward` / `money_reward` set in that enemy's scene to
## **the player who killed it** (`killed_by` on the enemy); if nobody knows who killed it (stomped, future traps) it goes to player 1.

## The roster changed (created, deleted, renamed); the save list refreshes from it.
signal roster_changed
## A seat changed hands.
signal seat_changed(index: int)

const BALANCE := "res://progression/balance.tres"
const DEFAULT_SAVE := "user://save.json"
## Project names from before a rename. `user://` follows `application/config/name`; in 2026-11 it changed from FirstGame to ZONE BREAKER,
## and the save folder changed with it — if the old folder has a save and the new one does not yet, it is moved over once (`_adopt_old_save()`).
const OLD_NAMES := ["FirstGame"]
## Characters without a name (migrated from old saves, created on the spot in tests) are named after their seat.
const DEFAULT_NAMES := ["PLAYER 1", "PLAYER 2"]
## When no look was picked each seat gets its own, so the two players do not look the same in co-op.
## What a new character looks like by default: **seat N gets entry N of the list** (`Catalog.looks()`),
## so two players never look the same by default. The list comes from scanning `characters/`, not named here.

## Whether to read and write the save. Tests turn it off.
var persist := true
var save_path := DEFAULT_SAVE
var balance: Balance

## Every character in the save.
var roster: Array[PlayerProgress] = []

## Seat → the character sitting there now; the index is `Player.player_index`. **Created only when needed** (in `of()`),
## so playing alone does not conjure up an unplayed player 2 character taking a row in the save list.
## **A seated character is always in the roster**: anything with progress should be saved, and the roster is "which characters the save holds".
var _seats: Array[PlayerProgress] = []


func _ready() -> void:
	balance = load(BALANCE) as Balance
	new_game()
	if persist:
		load_game()
	GameEvents.event_happened.connect(_on_event)


# ---------------------------------------------------------------- Seats

## The character a player is using now (out of range counts as player 1, so a missing index somewhere does not crash).
func of(index: int) -> PlayerProgress:
	var seat := clampi(index, 0, _seats.size() - 1)
	if _seats[seat] == null:
		_seats[seat] = fresh(seat)
	return _seats[seat]


## Put a roster character in a seat. The same character cannot sit in two seats at once — if it is already in another seat,
## that seat gets a new character instead (the UI should stop this first; this is only a safety net).
func take_seat(index: int, profile: PlayerProgress) -> void:
	if profile == null or index < 0 or index >= _seats.size():
		return
	for other in _seats.size():
		if other != index and _seats[other] == profile:
			_seats[other] = null
			seat_changed.emit(other)
	# **One created with NEW and then abandoned does not stay in the roster**: every NEW in the menu creates a character on the spot,
	# and going back to choose again left the previous one in the save list for ever — a player built up a dozen empty, unplayed characters in one evening.
	# Only the "never played for a minute, never changed at all" kind is dropped; ones that were actually set up are kept.
	var leaving := _seats[index]
	if leaving != null and leaving != profile and leaving.is_untouched():
		roster.erase(leaving)
		roster_changed.emit()
	_seats[index] = profile
	seat_changed.emit(index)
	save_game()


## Which seat this character is sitting in, -1 if nobody is using it.
func seat_of(profile: PlayerProgress) -> int:
	return _seats.find(profile)


# ---------------------------------------------------------------- Roster

## Is the name taken (a clash with the `except` character itself does not count)?
func name_taken(character_name: String, except: PlayerProgress = null) -> bool:
	var wanted := PlayerProgress.sanitize_name(character_name)
	for profile in roster:
		if profile != except and profile.character_name == wanted:
			return true
	return false


## Create a character and add it to the roster. Not created if the name is a duplicate or empty; returns null then.
func create(character_name: String, look := PlayerProgress.DEFAULT_LOOK) -> PlayerProgress:
	var wanted := PlayerProgress.sanitize_name(character_name)
	if wanted.is_empty() or name_taken(wanted):
		return null
	var profile := _new_profile()
	profile.character_name = wanted
	profile.look = look
	roster.append(profile)
	roster_changed.emit()
	save_game()
	return profile


## Delete a character from the roster. If it is sitting in a seat, that seat gets a new character.
func remove(profile: PlayerProgress) -> void:
	if profile == null or not roster.has(profile):
		return
	roster.erase(profile)
	for index in _seats.size():
		if _seats[index] == profile:
			_seats[index] = null
			seat_changed.emit(index)
	roster_changed.emit()
	save_game()


## The roster sorted by last save time, newest first (the save list is shown in this order).
func by_recent() -> Array[PlayerProgress]:
	var sorted := roster.duplicate()
	sorted.sort_custom(func(a: PlayerProgress, b: PlayerProgress) -> bool: return a.saved_at > b.saved_at)
	return sorted


## Start everything over: empty the roster and create a character for each seat. **The save file is not touched** (it is overwritten on the next change).
func new_game() -> void:
	roster.clear()
	_seats.clear()
	_seats.resize(Session.MAX_PLAYERS)


# ---------------------------------------------------------------- Play time

## Called every frame in a stage (`main.gd`). Menus and pause do not count, so the stage is in charge of this rather than running it here.
func tick_playtime(delta: float) -> void:
	for profile in _seats:
		if profile != null:
			profile.played_seconds += delta


# ---------------------------------------------------------------- Save file

func save_game() -> void:
	if not persist:
		return
	var now := Time.get_datetime_string_from_system()
	for profile in _seats:
		if profile != null:
			profile.saved_at = now
	# A seat records **the character's position in the roster**, not its name: names are changed by players, and a duplicate would pick the wrong character
	var data := {
		"characters": roster.map(func(p: PlayerProgress) -> Dictionary: return p.to_dict()),
		"seats": _seats.map(func(p: PlayerProgress) -> int: return roster.find(p) if p != null else -1),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


## If the project was renamed, copy the save over from the old name's folder (only once: if the new folder already has one, nothing happens).
## Copy rather than move: if the new version has a problem, the save is still where it was for the old version.
## `target` is the full path of the new save, `parent` the level that holds the per-project data folders (tests pass a temporary folder).
## Returns true if a save was copied over.
func adopt_old_save(target: String, parent: String) -> bool:
	if FileAccess.file_exists(target):
		return false
	for old_name: String in OLD_NAMES:
		var old := parent.path_join(old_name).path_join("save.json")
		if FileAccess.file_exists(old):
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			return DirAccess.copy_absolute(old, target) == OK
	return false


## Read the save; with no save or a broken one, keep the new-game state.
func load_game() -> void:
	if save_path == DEFAULT_SAVE:
		adopt_old_save(ProjectSettings.globalize_path(DEFAULT_SAVE), OS.get_user_data_dir().get_base_dir())
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_warning("Progress: can't read the save, starting a new game: %s" % save_path)
		return
	var saved: Array = _characters_in(data as Dictionary)
	if saved.is_empty():
		return
	roster.clear()
	for entry in saved:
		if not entry is Dictionary:
			continue
		var profile := _new_profile()
		profile.from_dict(entry)
		# Give a name to the nameless, and **fix duplicates on the spot too**: old saves may already have piled up several with the same name
		# (see the `_free_name` note); left as they are, the list would show identical rows and seats would pick the wrong character.
		if profile.character_name.is_empty():
			profile.character_name = _free_name(DEFAULT_NAMES[mini(roster.size(), DEFAULT_NAMES.size() - 1)])
		elif name_taken(profile.character_name):
			profile.character_name = _free_name(profile.character_name)
		roster.append(profile)
	# Seats: find whoever sat there last time; if not found, take roster characters in order; if the roster has none, leave it empty
	# until a player really sits down (`of()`) and create one then, so playing alone does not leave an unplayed player 2 in the roster.
	var wanted: Array = (data as Dictionary).get("seats", [])
	for index in _seats.size():
		var seated := _seated(wanted[index]) if index < wanted.size() else null
		if seated == null and index < roster.size():
			seated = roster[index]
		_seats[index] = seated
	roster_changed.emit()


## The list of characters in the save. Old formats are accepted too:
## `{"players": [a, b]}` is the version from before co-op (one per seat), and earlier still a single progress record sat at the top level.
func _characters_in(data: Dictionary) -> Array:
	if data.has("characters"):
		return data["characters"]
	if data.has("players"):
		return data["players"]
	return [data] if data.has("level") else []


## Who sits in the seat recorded in the save. The new format is a roster index, **old saves record a name**; both are accepted.
func _seated(mark: Variant) -> PlayerProgress:
	if mark is float or mark is int:
		var at := int(mark)
		return roster[at] if at >= 0 and at < roster.size() else null
	return _find(String(mark))


func _find(character_name: String) -> PlayerProgress:
	for profile in roster:
		if profile.character_name == character_name:
			return profile
	return null


## Create a character on the spot and add it to the roster: whoever sits in a seat must be in the roster, or their progress could not be saved.
## The name starts from the seat (a number is added on a clash); the player can change it in character setup.
## Choosing NEW in the menu calls this, then `take_seat()` to sit it down.
func fresh(index: int) -> PlayerProgress:
	var profile := _new_profile()
	profile.character_name = _free_name(DEFAULT_NAMES[mini(index, DEFAULT_NAMES.size() - 1)])
	var looks := Catalog.looks()
	if not looks.is_empty():
		profile.look = looks[mini(index, looks.size() - 1)].key
	roster.append(profile)
	return profile


func _new_profile() -> PlayerProgress:
	var profile := PlayerProgress.new(balance)
	profile.changed.connect(save_game)
	return profile


## A name not yet taken: the wanted one first, with a number added on a clash.
##
## **Make room for the number before adding it**: names are at most `NAME_LIMIT` (10) characters, and appending then truncating
## turned `PLAYER 1` + ` 10` back into `PLAYER 1 1`; from 11 on every one truncated to the same string, all taken,
## and after counting through it handed back the duplicate as is — so a player's save piled up six identical `PLAYER 1`s
## (actually hit in 2026-09: a whole page of the save list with the same name, and seats picking the wrong character by name).
## With room made, every candidate's number suffix differs, so they are all distinct,
## and at most as many tries as there are characters in the roster are needed to find a free one.
func _free_name(wanted: String) -> String:
	if not name_taken(wanted):
		return wanted
	for n in range(2, roster.size() + 3):
		var suffix := " %d" % n
		var base := wanted.substr(0, PlayerProgress.NAME_LIMIT - suffix.length())
		var tried := PlayerProgress.sanitize_name(base + suffix)
		if not name_taken(tried):
			return tried
	return wanted


func _on_event(event: StringName, source: Node) -> void:
	if event != &"enemy_death" or source == null:
		return
	var killer: Variant = source.get(&"killed_by")
	var who := of(killer.player_index if killer is Player else 0)
	# Rewards also use this stage's multiplier: the further the stage, the more an enemy is worth (`Stage`)
	var scale := Stage.reward_scale()
	who.add_money(roundi(int(source.get(&"money_reward")) * scale) if source.get(&"money_reward") != null else 0)
	who.add_xp(roundi(int(source.get(&"xp_reward")) * scale) if source.get(&"xp_reward") != null else 0)
