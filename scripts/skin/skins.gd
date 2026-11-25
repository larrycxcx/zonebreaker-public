extends Node
## The skin pack currently in use (the autoload singleton Skins).
## On start-up it reads the pack named by the project setting game/skin; use() switches it at run time.

signal skin_changed(skin: SkinPack)

const SETTING := "game/skin"
const DEFAULT_SKIN := "res://skins/default/default_skin.tres"

var current: SkinPack


func _ready() -> void:
	# The pack in the settings may be missing (the public build strips third-party art); then use the default pack (placeholder blocks + 8-bit sounds)
	var path: String = ProjectSettings.get_setting(SETTING, DEFAULT_SKIN)
	use(load(path if ResourceLoader.exists(path) else DEFAULT_SKIN) as SkinPack)


func use(skin: SkinPack) -> void:
	current = skin
	skin_changed.emit(skin)


## The default pack. Used by tests and as the fallback of custom packs.
func default_skin() -> SkinPack:
	return load(DEFAULT_SKIN) as SkinPack


func sound(event: StringName) -> AudioStream:
	return current.find_sound(event) if current != null else null


## A file in the current pack (or its fallback pack); an empty string if not found.
func file(relative: String) -> String:
	return current.find_file(relative) if current != null else ""


## The scene for an effect in the current pack; fallback_ (the default set on the Fx node) if there is none.
func effect(key: StringName, fallback_: PackedScene) -> PackedScene:
	var scene: PackedScene = current.find_effect(key) if current != null else null
	return scene if scene != null else fallback_


## The background music for a purpose in the current pack; null if there is none.
func music(key: StringName) -> AudioStream:
	return current.find_music(key) if current != null else null


## The current pack's HUD appearance scene; null if there is none.
func hud() -> PackedScene:
	return current.find_hud() if current != null else null


## The current pack's stage backdrop scene; null if there is none.
func backdrop() -> PackedScene:
	return current.find_backdrop() if current != null else null


func lighting() -> PackedScene:
	return current.find_lighting() if current != null else null


## Install the appearance for a skin key on owner and return the `Appearance` finally used.
## If the current pack lacks this key (or the scene is wrong) the look built into the character's scene stays — a mistake in a skin pack should not crash the game.
## Characters call this first thing in _ready, and from then on only deal with the appearance through the returned object.
func build_appearance(owner: Node, key: StringName) -> Appearance:
	var built_in := owner.get_node_or_null("Visual") as Appearance
	if key == &"" or current == null:
		return built_in
	var scene := current.find_appearance(key)
	if scene == null:
		return built_in
	var replacement := scene.instantiate() as Appearance
	if replacement == null:
		push_warning("the appearance root for %s in the skin pack has no Appearance script; keeping the default look" % key)
		return built_in
	replacement.name = "Visual"
	if built_in != null:
		var index := built_in.get_index()
		owner.remove_child(built_in)
		built_in.queue_free()
		owner.add_child(replacement)
		owner.move_child(replacement, index)
	else:
		owner.add_child(replacement)
	return replacement
