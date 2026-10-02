extends Node
## 当前使用的素材包（autoload 单例 Skins）。
## 启动时读取项目设置 game/skin 指定的包；运行中可以用 use() 切换。

signal skin_changed(skin: SkinPack)

const SETTING := "game/skin"
const DEFAULT_SKIN := "res://skins/default/default_skin.tres"

var current: SkinPack


func _ready() -> void:
	use(load(ProjectSettings.get_setting(SETTING, DEFAULT_SKIN)) as SkinPack)


func use(skin: SkinPack) -> void:
	current = skin
	skin_changed.emit(skin)


## 默认包。测试和自制素材包的 fallback 都会用到。
func default_skin() -> SkinPack:
	return load(DEFAULT_SKIN) as SkinPack


func sound(event: StringName) -> AudioStream:
	return current.find_sound(event) if current != null else null


## 当前包（或它的备用包）里的一个文件，找不到返回空串。
func file(relative: String) -> String:
	return current.find_file(relative) if current != null else ""


## 当前包里某个特效的场景，没有就返回 fallback_（Fx 节点上配的默认值）。
func effect(key: StringName, fallback_: PackedScene) -> PackedScene:
	var scene: PackedScene = current.find_effect(key) if current != null else null
	return scene if scene != null else fallback_


## 当前包里某个用途的背景音乐，没有返回 null。
func music(key: StringName) -> AudioStream:
	return current.find_music(key) if current != null else null


## 当前包的 HUD 外观场景，没有返回 null。
func hud() -> PackedScene:
	return current.find_hud() if current != null else null


## 当前包的关卡背景场景，没有返回 null。
func backdrop() -> PackedScene:
	return current.find_backdrop() if current != null else null


func lighting() -> PackedScene:
	return current.find_lighting() if current != null else null


## 按皮肤键给 owner 装上外观，返回最终用的那个 `Appearance`。
## 当前包里没有这个键（或者给的场景不对）就保留角色场景里自带的外观——皮肤包填错不该让游戏崩。
## 角色在 _ready 里第一时间调它，之后只通过返回的这个对象和外观打交道。
func build_appearance(owner: Node, key: StringName) -> Appearance:
	var built_in := owner.get_node_or_null("Visual") as Appearance
	if key == &"" or current == null:
		return built_in
	var scene := current.find_appearance(key)
	if scene == null:
		return built_in
	var replacement := scene.instantiate() as Appearance
	if replacement == null:
		push_warning("皮肤包里 %s 的外观根节点没有 Appearance 脚本，继续用默认外观" % key)
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
